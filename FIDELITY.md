# Docker workload fidelity

Every selectable source ref has a committed executable plan under `plans/<case>/refs/<ref>/.boringcache.toml`. The level below is part of the benchmark contract:

- `direct-step`: the plan projects a directly declared upstream Docker build step.
- `matrix-member`: the plan is one upstream architecture/member, not the aggregate release result.
- `wrapper-projection`: the plan projects the cache-relevant Docker solve hidden behind an upstream script or reusable workflow; it must not be presented as an exact top-level command comparison.
- `diagnostic-tool-cache` and `diagnostic-overlay`: explicit BoringCache experiments that differ from upstream and are not fidelity benchmarks.

Output is no longer a dispatch choice. Each case commits `none`, `load`, or `ghcr` from its upstream build phase, so a publishing workflow publishes and a validation workflow does not.

| Case | Fidelity | Output | Pinned upstream workflow |
|---|---|---|---|
| `anythingllm-primary` | `direct-step` | `ghcr` | [`.github/workflows/build-and-push-image.yaml`](https://github.com/Mintplex-Labs/anything-llm/actions/runs/29620753615/job/88015259352) |
| `anythingllm-primary-arm64` | `matrix-member` | `ghcr` | [`.github/workflows/build-and-push-image.yaml`](https://github.com/Mintplex-Labs/anything-llm/actions/runs/29620753615/job/88015259352) |
| `auto-mobile-docker` | `direct-step` | `ghcr` | [`.github/workflows/merge.yml`](https://github.com/kaeawc/auto-mobile/actions/runs/20904260051/job/60055768837) |
| `biar-automation-orchestrator` | `direct-step` | `ghcr` | [`.github/workflows/dockerhub-image-build-multi.yml`](https://github.com/tazama-lf/biar/actions/runs/30026601442) |
| `biar-datalakehouse-api` | `direct-step` | `ghcr` | [`.github/workflows/dockerhub-image-build-multi.yml`](https://github.com/tazama-lf/biar/actions/runs/30026601442) |
| `biar-jupyterhub` | `direct-step` | `ghcr` | [`.github/workflows/dockerhub-image-build-multi.yml`](https://github.com/tazama-lf/biar/actions/runs/30026601442) |
| `blockscout-frontend` | `wrapper-projection` | `ghcr` | [`.github/workflows/deploy-review.yml`](https://github.com/blockscout/frontend/actions/runs/30473737168) |
| `cardstack-realm-server` | `wrapper-projection` | `ghcr` | [`.github/workflows/manual-deploy.yml`](https://github.com/cardstack/boxel/actions/runs/25861223646) |
| `chatwoot-docker` | `direct-step` | `none` | [`.github/workflows/test_docker_build.yml`](https://github.com/chatwoot/chatwoot/actions/runs/29762401159/job/88419967813) |
| `cloudcost-exporter-amd64` | `wrapper-projection` | `none` | [`.github/workflows/build-on-feature-branch.yml`](https://github.com/grafana/cloudcost-exporter/actions/runs/27209558109/job/80335379406) |
| `cloudcost-exporter-amd64-go` | `diagnostic-tool-cache` | `none` | [`.github/workflows/build-on-feature-branch.yml`](https://github.com/grafana/cloudcost-exporter/actions/runs/27209558109/job/80335379406) |
| `dependabot-updater-core` | `wrapper-projection` | `load` | [`.github/workflows/smoke.yml`](https://github.com/dependabot/dependabot-core/actions/runs/27011845235) |
| `formbricks-web` | `direct-step` | `load` | [`.github/workflows/docker-build-validation.yml`](https://github.com/formbricks/formbricks/actions/runs/29744679758/job/88359620840) |
| `ghostfolio-docker` | `direct-step` | `ghcr` | [`.github/workflows/docker-image.yml`](https://github.com/ghostfolio/ghostfolio/actions/runs/29765006006/job/88428936554) |
| `grist-oss` | `direct-step` | `ghcr` | [`.github/workflows/docker_latest.yml`](https://github.com/gristlabs/grist-core/actions/runs/29722168278/job/88287251647) |
| `heyform-community` | `direct-step` | `ghcr` | [`.github/workflows/publish-docker-image.yml`](https://github.com/HeyForm/heyform/actions/runs/29302628301/job/86989382002) |
| `hoppscotch-backend` | `matrix-member` | `ghcr` | [`.github/workflows/release-push-docker.yml`](https://github.com/hoppscotch/hoppscotch/actions/runs/29410411043/job/87335877154) |
| `hoppscotch-backend-arm64` | `matrix-member` | `ghcr` | [`.github/workflows/release-push-docker.yml`](https://github.com/hoppscotch/hoppscotch/actions/runs/29410411043/job/87335877176) |
| `iggy-rust-server` | `wrapper-projection` | `ghcr` | [`.github/workflows/publish.yml`](https://github.com/apache/iggy/actions/runs/24415263274) |
| `iggy-rust-server-sccache` | `diagnostic-overlay` | `ghcr` | [`.github/workflows/publish.yml`](https://github.com/apache/iggy/actions/runs/24415263274) |
| `karakeep-aio` | `direct-step` | `ghcr` | [`.github/workflows/docker.yml`](https://github.com/karakeep-app/karakeep/actions/runs/29655698063/job/88109521077) |
| `kvrocks-docker` | `direct-step` | `none` | [`.github/workflows/kvrocks.yaml`](https://github.com/apache/kvrocks/actions/runs/26924643510) |
| `kvrocks-docker-sccache` | `diagnostic-overlay` | `none` | [`.github/workflows/kvrocks.yaml`](https://github.com/apache/kvrocks/actions/runs/26924643510) |
| `misskey-develop-amd64` | `matrix-member` | `ghcr` | [`.github/workflows/docker-develop.yml`](https://github.com/misskey-dev/misskey/actions/runs/29795853045/job/88526918315) |
| `mozilla-bedrock-release` | `wrapper-projection` | `ghcr` | [`.github/workflows/build-and-push.yml`](https://github.com/mozilla/bedrock/actions/runs/29589233619) |
| `mozilla-fxa-mono` | `direct-step` | `ghcr` | [`.github/workflows/docker.yml`](https://github.com/mozilla/fxa/pull/19848) |
| `nmisp-nightly` | `direct-step` | `ghcr` | [`.github/workflows/build-test-image.yml`](https://github.com/kangwonlee/nmisp/actions/runs/24956177996/job/73074709808) |
| `omninode-runtime` | `direct-step` | `ghcr` | [`.github/workflows/docker-build.yml`](https://github.com/OmniNode-ai/omnibase_infra/pull/567) |
| `open-webui-ollama` | `direct-step` | `ghcr` | [`.github/workflows/docker.yaml`](https://github.com/open-webui/open-webui/actions/runs/29719425583/job/88279690630) |
| `openstatus-dashboard` | `direct-step` | `ghcr` | [`.github/workflows/docker-publish.yml`](https://github.com/openstatusHQ/openstatus/actions/runs/29770045286/job/88445656341) |
| `openstatus-dashboard-arm64` | `matrix-member` | `ghcr` | [`.github/workflows/docker-publish.yml`](https://github.com/openstatusHQ/openstatus/actions/runs/29770045286/job/88445656341) |
| `phentrieve-api` | `direct-step` | `ghcr` | [`.github/workflows/docker-publish.yml`](https://github.com/berntpopp/phentrieve/actions/runs/26311969942/job/77462686222) |
| `posit-connect-content-amd64` | `wrapper-projection` | `ghcr` | [`.github/workflows/content.yml`](https://github.com/posit-dev/images-connect/actions/runs/30313698156/job/90283968450) |
| `prefect-conda` | `direct-step` | `ghcr` | [`.github/workflows/docker-images.yaml`](https://github.com/PrefectHQ/prefect/actions/runs/29637767387/job/88062987619) |
| `proteus-controller-multiarch` | `diagnostic-overlay` | `ghcr` | [`.github/workflows/image.yml`](https://github.com/CraftingTech/proteus/actions/runs/30160511674) |
| `pythonitalia-pycon-pretix` | `direct-step` | `ghcr` | [`.github/workflows/build-pretix.yml`](https://github.com/pythonitalia/pycon/issues/4536) |
| `stirling-pdf-embedded` | `matrix-member` | `ghcr` | [`.github/workflows/push-docker.yml`](https://github.com/Stirling-Tools/Stirling-PDF/actions/runs/29758033815/job/88405425988) |
| `supabase-storage-api` | `matrix-member` | `ghcr` | [`.github/workflows/release.yml`](https://github.com/supabase/storage/actions/runs/30003831969/job/89195263961) |
| `supabase-storage-api-arm64` | `matrix-member` | `ghcr` | [`.github/workflows/release.yml`](https://github.com/supabase/storage/actions/runs/30003831969/job/89195263961) |
| `supabase-studio` | `direct-step` | `ghcr` | [`.github/workflows/publish_image.yml`](https://github.com/supabase/supabase/actions/runs/29718726330/job/88276984110) |
| `teable-community` | `direct-step` | `ghcr` | [`.github/workflows/docker-push.yml`](https://github.com/teableio/teable/actions/runs/29639339391/job/88067090491) |
| `tiled-container-canary` | `direct-step` | `none` | [`.github/workflows/ci.yml`](https://github.com/bluesky/tiled/actions/runs/30610469144/job/91091895475) |
| `typebot-builder` | `matrix-member` | `ghcr` | [`.github/workflows/release.yml`](https://github.com/baptisteArno/typebot.io/actions/runs/27695467686/job/81917369215) |
| `umami-release` | `direct-step` | `ghcr` | [`.github/workflows/cd.yml`](https://github.com/umami-software/umami/actions/runs/28136102295/job/83323168828) |
| `vellum-assistant` | `matrix-member` | `ghcr` | [`.github/workflows/dev-release.yaml`](https://github.com/vellum-ai/vellum-assistant/actions/runs/29803174296/job/88549285230) |
| `windmill-extra` | `matrix-member` | `ghcr` | [`.github/workflows/publish_extra.yml`](https://github.com/windmill-labs/windmill/actions/runs/30081039014/job/89445412474) |
| `wormhole-solana` | `direct-step` | `ghcr` | [`.github/workflows/tilt-images.yml`](https://github.com/wormhole-foundation/native-token-transfers/actions/runs/26104579611/job/76764717136) |
