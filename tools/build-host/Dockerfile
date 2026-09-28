# Build container for hosts that are not Ubuntu/Debian (Oracle Linux, Fedora, Arch, ...).
#   docker build -t lineage-build .
#   docker run -it --rm -v $HOME/android:/home/build/android -v $HOME/.ccache:/home/build/.ccache lineage-build
# then run sync-and-build.sh inside. The source lives on the host, the container holds only tools.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs gnupg \
    gperf imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev \
    libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc xxd zip zlib1g-dev meson glslang-tools python3-mako python3-yaml python3-pycparser python3-jinja2 python3-ply \
    python3 python-is-python3 openssh-client ca-certificates sudo tmux \
    unzip cpio kmod file less procps \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo && chmod a+x /usr/local/bin/repo
ARG UID=1000
RUN useradd -m -u $UID build
USER build
WORKDIR /home/build
ENV USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache
RUN git config --global user.name "Yaron Shahrabani" && git config --global user.email "yarons@users.noreply.github.com" \
 && git config --global color.ui false && git lfs install --skip-repo
CMD ["bash", "-l"]
