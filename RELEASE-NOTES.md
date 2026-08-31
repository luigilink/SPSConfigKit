# SPSConfigKit - Release Notes

## [1.7.2] - 2026-08-31

### Fixed

- Search topology now accepts nodes with the `ApplicationWithSearch` MinRole (#52)
  - The six `SPSearchTopology` component assignments in `CfgAppSps`
    (`Admin`, `Crawler`, `ContentProcessing`, `AnalyticsProcessing`, `QueryProcessing`,
    `IndexPartition`) filtered strictly on `SPServerRole -eq 'Search'`. A node declared with
    the documented `ApplicationWithSearch` MinRole (a combined Application + Search server)
    and the six `Is*` component flags matched none of them, so the Search Service Application
    topology was provisioned empty on a 2-server farm with no dedicated `Search` node. The
    filters now accept both roles (`SPServerRole -in @('Search', 'ApplicationWithSearch')`).
  - A commented 2-server example (a combined `ApplicationWithSearch` node + a
    `WebFrontEndWithDistributedCache` node) ships in `scripts/sps/CfgAppSps.psd1`, and
    `wiki/Configuration.md` documents the combined-node scenario.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
