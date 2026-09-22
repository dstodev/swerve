IMAGE_TAG ?= swerve-test
APP_USER ?= user

export IMAGE_TAG
export APP_USER

TEST_LOG ?= test.log

.DEFAULT_GOAL := help

help: ## Show this help
	@echo 'Usage: make [TARGET]'
	@echo
	@echo 'Targets:'
	@grep -hE '^[a-zA-Z0-9_. -]+:.*##' $(MAKEFILE_LIST) | \
		awk -F ':.*##[ \t]*' '{ \
			name = $$1; gsub(/ +/, ", ", name); \
			names[NR] = name; descs[NR] = $$2; \
			if (length(name) > width) width = length(name) \
		} END { \
			for (i = 1; i <= NR; i++) \
				printf "  %-*s  %s\n", width, names[i], descs[i] \
		}'
.PHONY: help

image: ## Build the Docker image
	docker build --build-arg USER_NAME=$(APP_USER) --tag $(IMAGE_TAG) docker
.PHONY: image

shell sh: image ## Open a shell in the Docker image
	docker run --rm --interactive --tty --entrypoint sh $(IMAGE_TAG)
.PHONY: shell sh

lint: ## Run static checks
	./script/lint.sh
.PHONY: lint

test: SHELL := bash
test: ## Build, run, and assert invariants
	./script/test.sh 2>&1 | tee $(TEST_LOG); exit "$${PIPESTATUS[0]}"
.PHONY: test
