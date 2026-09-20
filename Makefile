IMAGE_TAG ?= swerve-app-demo
APP_USER ?= user

export IMAGE_TAG
export APP_USER

RUN_LOG ?= run.log

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Available targets:"
	@grep -hE '^[a-zA-Z0-9_. -]+:.*##' $(MAKEFILE_LIST) | \
		awk -F ':.*##[ \t]*' '{ printf "  %-10s %s\n", $$1, $$2 }'
.PHONY: help

image: ## Build the image
	docker build --build-arg USER_NAME=$(APP_USER) --tag $(IMAGE_TAG) docker
.PHONY: image

run: SHELL := bash
run: ## Build and run the container
	./run.sh 2>&1 | tee $(RUN_LOG); exit "$${PIPESTATUS[0]}"
.PHONY: run

shell sh: image ## Open a shell in the image
	docker run --rm --interactive --tty --entrypoint sh $(IMAGE_TAG)
.PHONY: shell sh
