//! Native Switch 2 stereo PCM audio output via libounce `audout`.

#[cfg(target_os = "horizon")]
mod imp {
    use std::alloc::{Layout, alloc_zeroed, dealloc};
    use std::ffi::c_void;
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };

    const BUF_ALIGN: usize = 0x1000;
    const BUF_BYTES: usize = 0x4000;
    const FRAMES_PER_BUF: usize = 1024;
    const WAIT_TIMEOUT_NS: u64 = 100_000_000;

    #[repr(C)]
    struct AudioOutBuffer {
        next: *mut AudioOutBuffer,
        buffer: *mut c_void,
        buffer_size: u64,
        data_size: u64,
        data_offset: u64,
    }

    unsafe extern "C" {
        fn audoutInitialize() -> u32;
        fn audoutExit();
        fn audoutStartAudioOut() -> u32;
        fn audoutStopAudioOut() -> u32;
        fn audoutAppendAudioOutBuffer(buf: *mut AudioOutBuffer) -> u32;
        fn audoutWaitPlayFinish(
            released: *mut *mut AudioOutBuffer,
            released_count: *mut u32,
            timeout: u64,
        ) -> u32;
        fn audoutGetSampleRate() -> u32;
        fn audoutGetChannelCount() -> u32;
    }

    /// Active Switch `audout` playback stream; stops cleanly when dropped.
    pub struct AudioOutStream {
        stop: Arc<AtomicBool>,
        thread: Option<std::thread::JoinHandle<()>>,
    }

    impl Drop for AudioOutStream {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Release);
            if let Some(handle) = self.thread.take() {
                let _ = handle.join();
            }
        }
    }

    fn fill_buffer<F: FnMut(&mut [f32], usize, u32)>(
        render: &mut F,
        scratch: &mut Vec<f32>,
        buf_ptr: *mut c_void,
        channels: usize,
        rate: u32,
    ) -> usize {
        let samples = FRAMES_PER_BUF * channels;
        scratch.resize(samples, 0.0);
        render(scratch, channels, rate);
        let dst = unsafe { std::slice::from_raw_parts_mut(buf_ptr.cast::<i16>(), samples) };
        for (out, &s) in dst.iter_mut().zip(scratch.iter()) {
            *out = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
        }
        samples * std::mem::size_of::<i16>()
    }

    impl AudioOutStream {
        /// Starts a double-buffered `audout` thread calling `render(buf, channels, sample_rate)`.
        pub fn open<F>(mut render: F) -> Result<Self, String>
        where
            F: FnMut(&mut [f32], usize, u32) + Send + 'static,
        {
            let rc = unsafe { audoutInitialize() };
            if rc != 0 {
                return Err(format!("audoutInitialize failed: 0x{rc:x}"));
            }
            let rc = unsafe { audoutStartAudioOut() };
            if rc != 0 {
                unsafe { audoutExit() };
                return Err(format!("audoutStartAudioOut failed: 0x{rc:x}"));
            }
            let rate = unsafe { audoutGetSampleRate() }.max(48000);
            let channels = (unsafe { audoutGetChannelCount() } as usize).clamp(1, 2);
            log::info!("Horizon: Switch 2 audout active ({rate} Hz, {channels} ch, i16 PCM)");

            let stop = Arc::new(AtomicBool::new(false));
            let stop_thread = stop.clone();
            let thread = std::thread::Builder::new()
                .name("horizon-audout".into())
                .spawn(move || {
                    let layout = Layout::from_size_align(BUF_BYTES, BUF_ALIGN).unwrap();
                    let mem = [
                        unsafe { alloc_zeroed(layout) }.cast::<c_void>(),
                        unsafe { alloc_zeroed(layout) }.cast::<c_void>(),
                    ];
                    if mem[0].is_null() || mem[1].is_null() {
                        for p in mem {
                            if !p.is_null() {
                                unsafe { dealloc(p.cast::<u8>(), layout) };
                            }
                        }
                        unsafe {
                            let _ = audoutStopAudioOut();
                            audoutExit();
                        }
                        return;
                    }
                    let mut bufs = [
                        Box::new(AudioOutBuffer {
                            next: std::ptr::null_mut(),
                            buffer: mem[0],
                            buffer_size: BUF_BYTES as u64,
                            data_size: 0,
                            data_offset: 0,
                        }),
                        Box::new(AudioOutBuffer {
                            next: std::ptr::null_mut(),
                            buffer: mem[1],
                            buffer_size: BUF_BYTES as u64,
                            data_size: 0,
                            data_offset: 0,
                        }),
                    ];
                    let mut scratch = Vec::with_capacity(FRAMES_PER_BUF * channels);
                    for buf in &mut bufs {
                        buf.data_size =
                            fill_buffer(&mut render, &mut scratch, buf.buffer, channels, rate)
                                as u64;
                        let _ = unsafe { audoutAppendAudioOutBuffer(&mut **buf) };
                    }
                    while !stop_thread.load(Ordering::Acquire) {
                        let mut released: *mut AudioOutBuffer = std::ptr::null_mut();
                        let mut count: u32 = 0;
                        let rc = unsafe {
                            audoutWaitPlayFinish(&mut released, &mut count, WAIT_TIMEOUT_NS)
                        };
                        if rc == 0 && count > 0 && !released.is_null() {
                            let buf = unsafe { &mut *released };
                            buf.data_size =
                                fill_buffer(&mut render, &mut scratch, buf.buffer, channels, rate)
                                    as u64;
                            let _ = unsafe { audoutAppendAudioOutBuffer(buf) };
                        }
                    }
                    unsafe {
                        let _ = audoutStopAudioOut();
                        audoutExit();
                    }
                    drop(bufs);
                    for p in mem {
                        unsafe { dealloc(p.cast::<u8>(), layout) };
                    }
                })
                .map_err(|e| format!("failed to spawn horizon-audout thread: {e}"))?;
            Ok(Self {
                stop,
                thread: Some(thread),
            })
        }
    }
}

#[cfg(target_os = "horizon")]
pub use imp::AudioOutStream;
