# Build environment for Horizon on Switch 2.
FROM ounce-devkit:local

ENV RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    RUST_NIGHTLY=nightly-2026-07-02
ENV PATH=/opt/rust/cargo/bin:$PATH

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "$RUST_NIGHTLY" --component rust-src,rustfmt && \
    chmod -R a+rwX /opt/rust

WORKDIR /src
