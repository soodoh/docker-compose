# syntax=docker/dockerfile:1

# Pin the GoW runtime so emulator changes are reviewed and deployed together.
ARG ES_DE_BASE_IMAGE=ghcr.io/games-on-whales/es-de@sha256:f5d1037e9dd6ff7406e190e00457152d0a9dcb4adbc32fe2132585cb5bbe7829
FROM ${ES_DE_BASE_IMAGE}

# melonDS DS v1.2.0, official x86-64 release archive.
ADD --checksum=sha256:9b7c1ef08a9ed3d1a61be3981cf40332c88ce3f59ca76336262701b27dabdb2b \
    https://github.com/JesseTG/melonds-ds/releases/download/v1.2.0/melondsds_libretro-linux-x86_64-Release.zip \
    /tmp/melondsds.zip

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libretro-mgba=0.10.5+dfsg-1 \
        unzip \
    && unzip -p /tmp/melondsds.zip '*/cores/melondsds_libretro.so' > /usr/lib/x86_64-linux-gnu/libretro/melondsds_libretro.so \
    && unzip -p /tmp/melondsds.zip '*/cores/melondsds_libretro.info' > /usr/share/libretro/info/melondsds_libretro.info \
    && chmod 0644 \
        /usr/lib/x86_64-linux-gnu/libretro/melondsds_libretro.so \
        /usr/share/libretro/info/melondsds_libretro.info \
    && test -f /usr/lib/x86_64-linux-gnu/libretro/mgba_libretro.so \
    && test -f /usr/lib/x86_64-linux-gnu/libretro/melondsds_libretro.so \
    && rm -f /tmp/melondsds.zip \
    && rm -rf /var/lib/apt/lists/*

# Make the image-provided melonDS DS core the default Nintendo DS emulator.
COPY es_systems.xml /cfg/es/es_systems.xml


# Use packaged RetroArch profiles and add Wolf's virtual Xbox controller.
COPY retroarch.cfg /cfg/retroarch/retroarch.cfg
COPY wolf-xbox-one.cfg /usr/share/libretro/autoconfig/Wolf_X-Box_One_virtual_pad.cfg
