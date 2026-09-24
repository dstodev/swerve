MAKEFLAGS += --no-builtin-rules --warn-undefined-variables
.DELETE_ON_ERROR:

IMAGE_TAG ?= swerve-test
APP_USER ?= user

export IMAGE_TAG
export APP_USER

# Tracked and untracked files, minus .gitignore, minus deleted-but-tracked
repo_files = $(sort $(wildcard $(shell \
		git ls-files --cached --others --exclude-standard -- \
			$(foreach pattern,$(1),'$(pattern)'))))

TEST_LOG ?= test.log
LINT_IMAGE ?= $(IMAGE_TAG)-lint
LINT_RUN = docker run --rm \
		--volume "$(CURDIR):$(CURDIR):ro" \
		--workdir "$(CURDIR)" \
		$(LINT_IMAGE)

required_files = $(or $(call repo_files,$(1)), \
		$(error No $(2) found; is this a git checkout?))

SHELL_SOURCES = $(call required_files,*.sh,shell sources)
C_CXX_SOURCES = $(call required_files, \
		*.c *.h *.cc *.cpp *.cxx *.hh *.hpp *.hxx,C/C++ sources)

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
	docker build --build-arg USER_NAME=$(APP_USER) --tag $(IMAGE_TAG) \
		--file docker/app.Dockerfile docker
.PHONY: image

shell sh: image ## Open a shell in the Docker image
	docker run --rm --interactive --tty --entrypoint sh $(IMAGE_TAG)
.PHONY: shell sh

lint: shellcheck clang-format clang-tidy ## Run static checks
.PHONY: lint

lint-image: ## Build the lint tools image
	docker build --tag $(LINT_IMAGE) - < docker/lint.Dockerfile
.PHONY: lint-image

shellcheck: lint-image ## Run ShellCheck on shell scripts
	$(LINT_RUN) shellcheck $(SHELL_SOURCES)
.PHONY: shellcheck

clang-format: lint-image ## Check C/C++ formatting against .clang-format
	$(LINT_RUN) clang-format --dry-run --Werror $(C_CXX_SOURCES)
.PHONY: clang-format

clang-tidy: lint-image ## Run clang-tidy on C/C++ sources
	$(LINT_RUN) clang-tidy $(C_CXX_SOURCES) --
.PHONY: clang-tidy

test: SHELL := bash
test: ## Build, run, and assert invariants
	./script/test.sh 2>&1 | tee $(TEST_LOG); exit "$${PIPESTATUS[0]}"
.PHONY: test

clean: ## Remove the test log, test containers, and Docker images
	rm --force $(TEST_LOG)
	docker ps --all --quiet --filter 'name=^$(IMAGE_TAG)(-|$$)' | \
		xargs --no-run-if-empty docker rm --force
	docker image rm --force $(IMAGE_TAG) $(LINT_IMAGE)
.PHONY: clean
