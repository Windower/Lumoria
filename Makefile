APP_ID := net.windower.Lumoria
-include .env

FLATPAK_MANIFEST ?= net.windower.Lumoria.local.yml
HOST_BUILDDIR ?= build-host
FLATPAK_BUILDDIR ?= builddir-flatpak
OSTREE_REPO ?= repo
CARGO_LOCK := rust/native/Cargo.lock
CARGO_SOURCES := cargo-sources.json

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

.PHONY: host host-run cargo-sources manifests.publish flatpak.deps flatpak.dev.build flatpak.dev.build-only flatpak.dev.run clean \
	dev.clean dev.sandbox dev.export dev.export-existing dev.repo.sync \
	dev.key.export dev.key.sync \
	dev.repo-file.generate dev.repo-file.sync \
	dev.verify dev.cdn.invalidate dev.signed dev.signed-check

host:
	@if [ ! -d "$(HOST_BUILDDIR)" ]; then meson setup "$(HOST_BUILDDIR)"; fi
	meson compile -C "$(HOST_BUILDDIR)"

host-run: host
	LUMORIA_MANIFESTS="$(CURDIR)/data/manifests" ./$(HOST_BUILDDIR)/src/lumoria

cargo-sources: $(CARGO_SOURCES)

$(CARGO_SOURCES): $(CARGO_LOCK) tools/generate-cargo-sources.sh
	./tools/generate-cargo-sources.sh $@

manifests.publish:
	./tools/publish-manifests.sh

flatpak.deps:
	flatpak install --user -y flathub \
		org.gnome.Platform//50 \
		org.gnome.Sdk//50 \
		org.freedesktop.Sdk.Extension.vala//25.08 \
		org.freedesktop.Sdk.Extension.rust-stable//25.08 \
		org.winehq.Wine//stable-25.08

flatpak.dev.build: $(CARGO_SOURCES)
	flatpak run org.flatpak.Builder \
		--user --install --install-deps-from=flathub --force-clean \
		"$(FLATPAK_BUILDDIR)" "$(FLATPAK_MANIFEST)"

flatpak.dev.run: flatpak.dev.build
	flatpak run --user "$(APP_ID)"

clean:
	rm -rf "$(HOST_BUILDDIR)" .flatpak-builder "$(FLATPAK_BUILDDIR)" "$(OSTREE_REPO)"

dev.clean:
	rm -rf "$(FLATPAK_BUILDDIR)" "$(OSTREE_REPO)"

dev.sandbox: $(CARGO_SOURCES)
	flatpak run org.flatpak.Builder \
		--force-clean --sandbox --user --install-deps-from=flathub \
		"$(FLATPAK_BUILDDIR)" "$(FLATPAK_MANIFEST)"

dev.export: dev.sandbox dev.export-existing

dev.export-existing:
	@test -d "$(FLATPAK_BUILDDIR)" || (echo "$(FLATPAK_BUILDDIR) missing; run make dev.sandbox first." && exit 1)
	@test -n "$(KEYID)" || echo "KEYID not set; exporting unsigned."
	rm -rf "$(OSTREE_REPO)"
	flatpak build-export --arch=x86_64 \
		$(if $(KEYID),--gpg-sign="$(KEYID)") \
		"$(OSTREE_REPO)" "$(FLATPAK_BUILDDIR)"
	$(if $(KEYID),flatpak build-update-repo --gpg-sign="$(KEYID)" --generate-static-deltas "$(OSTREE_REPO)")

dev.repo.sync:
	@test -n "$(S3_OSTREE_URI)" || (echo "S3_OSTREE_URI is required (ostree repo, e.g. s3://… for repo.lumoria.dev). R2_* in .env is only for make manifests.publish." && exit 1)
	aws s3 sync "./$(OSTREE_REPO)" "$(S3_OSTREE_URI)" --delete
	aws s3 cp "$(OSTREE_REPO)/summary" "$(S3_OSTREE_URI)/summary" $(S3_CP_FLAGS)
	aws s3 cp "$(OSTREE_REPO)/summary.sig" "$(S3_OSTREE_URI)/summary.sig" $(S3_CP_FLAGS) || true
	aws s3 rm "$(S3_OSTREE_URI)/summary.idx" || true
	aws s3 rm "$(S3_OSTREE_URI)/summary.idx.sig" || true
	aws s3 rm "$(S3_OSTREE_URI)/summaries" --recursive || true

dev.key.export:
	@test -n "$(KEYID)" || (echo "KEYID is required." && exit 1)
	gpg --armor --export "$(KEYID)" > "$(PUBLIC_KEY_ASC_FILE)"
	gpg --export "$(KEYID)" > "$(PUBLIC_KEY_FILE)"

dev.key.sync: dev.key.export
	aws s3 cp "./$(PUBLIC_KEY_FILE)" "$(S3_OSTREE_URI)/$(PUBLIC_KEY_FILE)" $(S3_CP_FLAGS)

dev.repo-file.generate: dev.key.export
	@test -n "$(REPO_HTTP_URL)" || (echo "REPO_HTTP_URL is required." && exit 1)
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

dev.repo-file.sync: dev.repo-file.generate
	aws s3 cp "./$(FLATPAK_REPO_FILE)" "$(S3_OSTREE_URI)/$(FLATPAK_REPO_FILE)" \
		--cache-control "$(SUMMARY_CACHE_CONTROL)" --content-type "application/vnd.flatpak.repo"

dev.verify:
	@echo "Verifying published repo endpoints..."
	@curl -fIsS "$(REPO_HTTP_URL)/summary" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/summary" && exit 1)
	@curl -fIsS "$(REPO_HTTP_URL)/$(PUBLIC_KEY_FILE)" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/$(PUBLIC_KEY_FILE)" && exit 1)
	@curl -fIsS "$(REPO_HTTP_URL)/$(FLATPAK_REPO_FILE)" >/dev/null || (echo "Unreachable: $(REPO_HTTP_URL)/$(FLATPAK_REPO_FILE)" && exit 1)
	@echo "Published endpoints look reachable."

dev.cdn.invalidate:
	@test -n "$(DIST_ID)" || (echo "DIST_ID is required." && exit 1)
	aws cloudfront create-invalidation \
		--distribution-id "$(DIST_ID)" \
		--paths "$(CLOUDFRONT_REPO_PATH)/*"

dev.signed-check:
	@test -n "$(KEYID)" || (echo "KEYID is required for dev.signed." && exit 1)
	@test -n "$(DIST_ID)" || (echo "DIST_ID is required for dev.signed (CloudFront for repo.lumoria.dev)." && exit 1)

dev.signed: dev.signed-check dev.clean dev.export dev.repo.sync dev.key.sync dev.repo-file.sync dev.verify dev.cdn.invalidate
