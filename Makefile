IMAGE_TAG ?= swerve-app-demo
APP_USER ?= user
RUN_LOG ?= run.log
export IMAGE_TAG
export APP_USER

.DEFAULT_GOAL := help

help:
	@echo "Available targets:"
	@awk -F: '/^[^\t.][^:]*:/ { print "  " $$1 }' $(MAKEFILE_LIST)
.PHONY: help

image:
	docker build --build-arg USER_NAME=$(APP_USER) --tag $(IMAGE_TAG) docker
.PHONY: image

run:
	exit_file=$$(mktemp); \
	{ ./run.sh 2>&1; echo $$? >"$$exit_file"; } | tee $(RUN_LOG); \
	status=$$(cat "$$exit_file"); rm --force "$$exit_file"; \
	exit "$$status"
.PHONY: run

shell sh: image
	docker run --rm --interactive --tty --entrypoint sh $(IMAGE_TAG)
.PHONY: shell sh
