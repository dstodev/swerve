FROM alpine:3 AS build

RUN apk add --no-cache gcc musl-dev
COPY keep-open.c /src/keep-open.c
RUN gcc -static -O2 -Wall -Wextra -Werror -o /keep-open /src/keep-open.c

FROM alpine:3

LABEL org.opencontainers.image.description='Minimal example: gosu/tini \
privilege drop with a FIFO-backed stdin channel'

ENV STDIN_PIPE=/run/stdin.pipe
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# No ARG dependency: keep this ahead of the ARGs below so overriding
# USER_ID or TZ at build time can't bust this (network-fetching) layer.
RUN apk add --no-cache \
	'gosu~1' \
	'tini~0' \
	tzdata

ARG TZ=America/Los_Angeles
ENV TZ=$TZ

RUN ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime \
	&& echo "$TZ" > /etc/timezone

ARG USER_ID=1000
ARG USER_NAME=user
ARG GROUP_ID=$USER_ID
ARG GROUP_NAME=$USER_NAME

ENV APP_USER=$USER_NAME
ENV APP_GROUP=$GROUP_NAME

RUN addgroup --gid "$GROUP_ID" "$GROUP_NAME" \
	&& adduser --uid "$USER_ID" --ingroup "$GROUP_NAME" \
	--disabled-password --gecos '' "$USER_NAME"

COPY --from=build \
     --chmod=0555 /keep-open /usr/local/bin/keep-open
COPY --chmod=0500 entrypoint.sh /usr/local/bin/
COPY --chmod=0555 app.sh leader.sh /usr/local/bin/

HEALTHCHECK CMD ["sh", "-c", "pgrep app.sh >/dev/null || exit 1"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
