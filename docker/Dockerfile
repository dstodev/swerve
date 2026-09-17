FROM alpine:3 AS build

RUN apk add --no-cache gcc musl-dev
COPY keep-open.c /src/keep-open.c
RUN gcc -static -O2 -Wall -Wextra -o /keep-open /src/keep-open.c

FROM alpine:3

LABEL org.opencontainers.image.description='Minimal example: gosu/tini \
privilege drop with a FIFO-backed stdin channel'

ARG USER_ID=1000
ARG USER_NAME=user
ARG GROUP_ID=$USER_ID
ARG GROUP_NAME=$USER_NAME
ARG TZ=America/Los_Angeles

ENV APP_USER=$USER_NAME
ENV APP_GROUP=$GROUP_NAME
ENV STDIN_PIPE=/run/stdin.pipe

ENV TZ=$TZ
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apk add --no-cache \
	'gosu~1' \
	'tini~0' \
	tzdata

RUN ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime \
	&& echo "$TZ" > /etc/timezone

RUN addgroup --gid "$GROUP_ID" "$GROUP_NAME" \
	&& adduser --uid "$USER_ID" --ingroup "$GROUP_NAME" \
	--disabled-password --gecos '' "$USER_NAME"

COPY --from=build --chmod=0755 /keep-open /usr/local/bin/keep-open
COPY --chmod=0755 entrypoint.sh /root/entrypoint.sh
COPY --chmod=0755 --chown=$USER_NAME:$GROUP_NAME \
	app.sh /home/$USER_NAME/app.sh
COPY --chmod=0755 --chown=$USER_NAME:$GROUP_NAME \
	leader.sh /home/$USER_NAME/leader.sh

HEALTHCHECK CMD pgrep app.sh >/dev/null || exit 1

ENTRYPOINT ["/root/entrypoint.sh"]
