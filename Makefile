APP_ID := net.windower.Lumoria
-include .env

FLATPAK_MANIFEST ?= net.windower.Lumoria.local.yml
HOST_BUILDDIR ?= build-host
FLATPAK_BUILDDIR ?= builddir-flatpak
OSTREE_REPO ?= repo

S3_OSTREE_URI ?=
REPO_HTTP_URL ?=
KEYID ?=
DIST_ID ?=

SUMMARY_CACHE_CONTROL ?= no-cache, no-store, must-revalidate
PUBLIC_KEY_FILE ?= lumoria-signing-public.gpg
PUBLIC_KEY_ASC_FILE ?= lumoria-signing-public.asc
RUNTIME_REPO_URL ?= https://dl.flathub.org/repo/flathub.flatpakrepo
FLATPAK_REPO_FILE ?= lumoria.flatpakrepo
REPO_TITLE ?= Lumoria
REPO_COMMENT ?= Lumoria Flatpak Repository
REPO_DESCRIPTION ?= Official Flatpak builds for Lumoria.
CLOUDFRONT_REPO_PATH ?=

S3_CP_FLAGS = --cache-control "$(SUMMARY_CACHE_CONTROL)" --content-type "application/octet-stream"

.PHONY: host host-run flatpak.dev.build flatpak.dev.build-only flatpak.dev.run clean \
	release.clean release.build release.export release.repo.sync \
	release.key.export release.key.sync \
	release.repo-file.generate release.repo-file.sync \
	release.verify release.cdn.invalidate release.signed

host:
	@if [ ! -d "$(HOST_BUILDDIR)" ]; then meson setup "$(HOST_BUILDDIR)"; fi
	meson compile -C "$(HOST_BUILDDIR)"

host-run: host
	./$(HOST_BUILDDIR)/src/lumoria

flatpak.dev.build:
	flatpak run org.flatpak.Builder \
		--user --install --force-clean \
		"$(FLATPAK_BUILDDIR)" "$(FLATPAK_MANIFEST)"

flatpak.dev.run: flatpak.dev.build
	flatpak run --user "$(APP_ID)"

clean:
	rm -rf "$(HOST_BUILDDIR)" .flatpak-builder "$(FLATPAK_BUILDDIR)" "$(OSTREE_REPO)"

release.clean:
	rm -rf "$(FLATPAK_BUILDDIR)" "$(OSTREE_REPO)"

release.build:
	flatpak run org.flatpak.Builder \
		--force-clean --sandbox --user \
		"$(FLATPAK_BUILDDIR)" "$(FLATPAK_MANIFEST)"

release.export: release.build
	@test -n "$(KEYID)" || echo "KEYID not set; exporting unsigned."
	rm -rf "$(OSTREE_REPO)"
	flatpak build-export --arch=x86_64 \
		$(if $(KEYID),--gpg-sign="$(KEYID)") \
		"$(OSTREE_REPO)" "$(FLATPAK_BUILDDIR)"
	$(if $(KEYID),flatpak build-update-repo --gpg-sign="$(KEYID)" --generate-static-deltas "$(OSTREE_REPO)")

release.repo.sync:
	aws s3 sync "./$(OSTREE_REPO)" "$(S3_OSTREE_URI)" --delete
	aws s3 cp "$(OSTREE_REPO)/summary" "$(S3_OSTREE_URI)/summary" $(S3_CP_FLAGS)
	aws s3 cp "$(OSTREE_REPO)/summary.sig" "$(S3_OSTREE_URI)/summary.sig" $(S3_CP_FLAGS) || true

release.key.export:
	@test -n "$(KEYID)" || (echo "KEYID is required." && exit 1)
	gpg --armor --export "$(KEYID)" > "$(PUBLIC_KEY_ASC_FILE)"
	gpg --export "$(KEYID)" > "$(PUBLIC_KEY_FILE)"

release.key.sync: release.key.export
	aws s3 cp "./$(PUBLIC_KEY_FILE)" "$(S3_OSTREE_URI)/$(PUBLIC_KEY_FILE)" $(S3_CP_FLAGS)

release.repo-file.generate: release.key.export
	@GPG_B64=$$(base64 -w0 "$(PUBLIC_KEY_FILE)" 2>/dev/null || base64 "$(PUBLIC_KEY_FILE)" | tr -d '\n'); \
	printf '%s\n' \
		'[Flatpak Repo]' \
		'Title=$(REPO_TITLE)' \
		'Comment=$(REPO_COMMENT)' \
		'Description=$(REPO_DESCRIPTION)' \
		'Url=$(REPO_HTTP_URL)' \
		'Homepage=$(REPO_HTTP_URL)' \
		'RuntimeRepo=$(RUNTIME_REPO_URL)' \
		"GPGKey=$$GPG_B64" \
		> "$(FLATPAK_REPO_FILE)"
	@echo "Wrote $(FLATPAK_REPO_FILE)"

release.repo-file.sync: release.repo-file.generate
	aws s3 cp "./$(FLATPAK_REPO_FILE)" "$(S3_OSTREE_URI)/$(FLATPAK_REPO_FILE)" \
		--cache-control "$(SUMMARY_CACHE_CONTROL)" --content-type "application/vnd.flatpak.repo"

release.verify:
	@echo "Verifying published repo endpoints..."
	@curl -fIsS "$(REPO_HTTP_URL)/summary" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/summary" && exit 1)
	@curl -fIsS "$(REPO_HTTP_URL)/$(PUBLIC_KEY_FILE)" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/$(PUBLIC_KEY_FILE)" && exit 1)
	@curl -fIsS "$(REPO_HTTP_URL)/$(FLATPAK_REPO_FILE)" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/$(FLATPAK_REPO_FILE)" && exit 1)
	@echo "Published endpoints look reachable."

release.cdn.invalidate:
	@test -n "$(DIST_ID)" || (echo "DIST_ID is required." && exit 1)
	aws cloudfront create-invalidation \
		--distribution-id "$(DIST_ID)" \
		--paths "$(CLOUDFRONT_REPO_PATH)/*"

release.signed: release.clean release.export release.repo.sync release.key.sync release.repo-file.sync release.verify
	@if [ -n "$(DIST_ID)" ]; then \
		$(MAKE) release.cdn.invalidate DIST_ID="$(DIST_ID)"; \
	else \
		echo "DIST_ID not set; skipping CDN invalidation."; \
	fi
