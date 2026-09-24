FROM alpine:3.22

# musl-dev, libstdc++-dev: C/C++ headers for clang-tidy to parse sources
RUN apk add --no-cache \
	clang20-extra-tools \
	libstdc++-dev \
	musl-dev \
	shellcheck
