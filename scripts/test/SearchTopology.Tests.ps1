<#
.SYNOPSIS
  Regression guard for the Search Service Application topology in scripts/sps/CfgAppSps.ps1:
  a node carrying the combined 'ApplicationWithSearch' MinRole must be placed in the search
  topology exactly like a dedicated 'Search' node.

.DESCRIPTION
  'ApplicationWithSearch' is a valid SPServerRole (MinRole). The six SPSearchTopology component
  assignments (Admin, Crawler, ContentProcessing, AnalyticsProcessing, QueryProcessing,
  IndexPartition) originally filtered strictly on SPServerRole -eq 'Search', so a combined
  Application+Search node (a 2-server farm with no dedicated Search node) produced an empty
  topology even though MinRole had deployed the role (issue #52). The filters now accept both
  roles via SPServerRole -in @('Search', 'ApplicationWithSearch').

  Two layers of checks, both cross-platform (no SharePoint modules / no MOF compilation):
    * a static guard on the shipped script (no strict -eq 'Search' topology filter survives,
      and all six components use the widened -in filter);
    * a behavioural check that replays the widened predicate against a synthetic 2-node farm
      and asserts every component resolves to the combined node.

.NOTES
  Requires Pester 5.0 or later.
#>

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
  # Component name -> node flag that places it, made available to -ForEach at discovery time.
  $Components = @(
    @{ Component = 'Admin'               ; Flag = 'IsSrcAdmin'  }
    @{ Component = 'Crawler'             ; Flag = 'IsSrcCrawl'  }
    @{ Component = 'ContentProcessing'   ; Flag = 'IsCntProc'   }
    @{ Component = 'AnalyticsProcessing' ; Flag = 'IsSrcAnalyt' }
    @{ Component = 'QueryProcessing'     ; Flag = 'IsSrcQuery'  }
    @{ Component = 'IndexPartition'      ; Flag = 'IsIndexPart' }
  )
}

BeforeAll {
  $script:ConfigScript = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'sps/CfgAppSps.ps1'
  if (-not (Test-Path -LiteralPath $script:ConfigScript)) {
    throw "CfgAppSps.ps1 not found at $script:ConfigScript"
  }
  $script:Lines = Get-Content -LiteralPath $script:ConfigScript

  # Synthetic 2-server farm: one combined Application+Search node carrying every search
  # component flag, plus a front-end node that must never appear in the topology.
  $script:AllNodes = @(
    [pscustomobject]@{
      NodeName = 'APP1'; IsSPSServer = $true; SPServerRole = 'ApplicationWithSearch'
      IsSrcAdmin = $true; IsSrcCrawl = $true; IsCntProc = $true
      IsSrcAnalyt = $true; IsSrcQuery = $true; IsIndexPart = $true
    },
    [pscustomobject]@{
      NodeName = 'WFE1'; IsSPSServer = $true; SPServerRole = 'WebFrontEndWithDistributedCache'
    }
  )
}

Describe 'CfgAppSps Search topology accepts ApplicationWithSearch (issue #52)' {

  Context 'static guard on the shipped script' {
    It 'no SPSearchTopology component filters strictly on SPServerRole -eq "Search"' {
      $strict = @($script:Lines | Where-Object { $_ -match 'SPServerRole\s+-eq\s+"Search"' })
      $strict.Count | Should -Be 0 -Because (
        'a strict -eq "Search" topology filter excludes ApplicationWithSearch nodes and leaves ' +
        'the Search topology empty on a 2-server farm (issue #52)'
      )
    }

    It 'all six components use SPServerRole -in @(''Search'', ''ApplicationWithSearch'')' {
      $widened = @($script:Lines | Where-Object { $_ -match "SPServerRole\s+-in\s+@\('Search',\s*'ApplicationWithSearch'\)" })
      $widened.Count | Should -Be 6 -Because 'each of the six SPSearchTopology components must accept both search roles'
    }
  }

  Context 'behavioural check on a synthetic 2-server farm' {
    It 'places the combined ApplicationWithSearch node in <Component>' -ForEach $Components {
      $nodeFlag = $Flag
      # Same predicate as the SPSearchTopology resource in CfgAppSps.ps1.
      $resolved = @($script:AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -in @('Search', 'ApplicationWithSearch') -and $_.$nodeFlag }.NodeName)
      $resolved | Should -Be @('APP1') -Because "the combined node carries $Flag and must own the $Component component"
    }

    It 'never places the WebFrontEndWithDistributedCache node in the topology' {
      foreach ($nodeFlag in @('IsSrcAdmin', 'IsSrcCrawl', 'IsCntProc', 'IsSrcAnalyt', 'IsSrcQuery', 'IsIndexPart')) {
        $resolved = @($script:AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -in @('Search', 'ApplicationWithSearch') -and $_.$nodeFlag }.NodeName)
        $resolved | Should -Not -Contain 'WFE1'
      }
    }
  }
}
