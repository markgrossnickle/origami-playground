# CodeMap: origami-playground

_275 files | 97,200 LOC | source: git ls-files_

## Stats

| Language | Files | LOC |
|---|---:|---:|
| Luau | 158 | 56,130 |
| JSON | 82 | 35,805 |
| Python | 10 | 2,269 |
| other | 7 | 422 |
| Markdown | 6 | 1,747 |
| TOML | 5 | 71 |
| YAML | 4 | 183 |
| Shell | 3 | 573 |

## Entry points

- `src/ReplicatedStorage/Client/ClientEntry.server.luau` — roblox server script
- `src/ServerScriptService/Server/Main.server.luau` — roblox server script

## Tree

```
scripts/  (1 files, 869 LOC)
src/  (155 files, 54,859 LOC)
  ReplicatedStorage/  (90 files, 44,565 LOC)
    Client/  (36 files, 15,855 LOC)
    Shared/  (54 files, 28,710 LOC)
  ServerScriptService/  (64 files, 10,288 LOC)
    Server/  (64 files, 10,288 LOC)
  ServerStorage/  (1 files, 6 LOC)
    Configuration/  (1 files, 6 LOC)
tests/  (14 files, 1,443 LOC)
  helpers/  (5 files, 461 LOC)
  unit/  (6 files, 589 LOC)
tools/  (82 files, 37,700 LOC)
... +6 asset-only directories (no code)
```

## Key files (40 of 275, ranked)

- `src/ReplicatedStorage/Shared/WorldGenModule.luau` (2537 L) **[<-5]**
  - WorldGenModule, :generateChunk(), :getSpawnPosition(), :getSurfaceWorldY(), :getSurfaceBlockY(), :getSeaLevelBlock(), :getWorldRadiusChunks(), :getStructureName(), :verifyDeterminism(), local _yieldIfBudgetExceeded(), local _resetBudget(), local hashSeed(), +20 more
- `src/ReplicatedStorage/Client/Controllers/BackpackController/init.luau` (1767 L) **[knit]**
  - BackpackController, :KnitInit(), :KnitStart(), :DespawnActiveCreature(), switchTab, local _materialNamespace(), local _materialCount(), local _canCraftTool(), local createCorner(), local clearChildren(), local formatMaterialName(), local formatTime(), +14 more
- `src/ReplicatedStorage/Client/Controllers/CreatorController/init.luau` (3089 L) **[knit]**
  - CreatorController, :OpenShop(), :CloseShop(), :KnitInit(), :KnitStart(), :GetSpawnedModels(), :RemoveSpawnedModel(), :RestartCreatureAI(), updateModelHighlights, updateStyleHighlights, updateCategoryHighlights, updateTypeHighlights, +33 more
- `src/ReplicatedStorage/Shared/BlockRegistry.luau` (1807 L) **[<-4]**
  - BlockRegistry, :get(), :getHardness(), :getColor(), :getMaterial(), :isMineable(), :isAir(), type BlockConfig
- `src/ReplicatedStorage/Client/Controllers/ChunkRenderController/init.luau` (1495 L) **[knit]**
  - ChunkRenderController, :GetBlockAt(), :GetChunkBlocks(), :GetActivePartCount(), :GetPoolSize(), :KnitInit(), :KnitStart(), local _getColor(), local _getMaterial(), local _tintColor(), local _applyRegionTint(), local _resolveChunkRegionTint(), +31 more
- `src/ServerScriptService/Server/Services/WorldService/init.luau` (1098 L) **[knit]**
  - WorldService, :PrefetchRegionsAround(), :GetOrCreateChunk(), :GetBlock(), :SetBlock(), :BreakBlock(), :Subscribe(), :Unsubscribe(), :UnsubscribeAll(), :GetPlayerSubscriptions(), :IsSubscribed(), :SetSlotOccupant(), +27 more
- `src/ReplicatedStorage/Shared/DemoModels.luau` (1796 L) **[<-1]**
  - DemoModels, :FindMatch()
- `src/ReplicatedStorage/Shared/CompetitionData.luau` (11971 L) **[<-1]**
  - CompetitionData
- `src/ReplicatedStorage/Shared/DemoShowcase.luau` (2718 L) **[<-1]**
  - DemoShowcase
- `src/ReplicatedStorage/Shared/ChunkUtil.luau` (133 L) **[<-12]**
  - ChunkUtil, :worldToChunk(), :chunkToWorld(), :chunkCenter(), :worldToLocalBlock(), :flatIndex(), :fromFlatIndex(), :chunkKey(), :parseChunkKey(), :chunkKeyFromString(), :chunkKeyToString(), :worldToFlatIndex(), +4 more
- `src/ReplicatedStorage/Client/Controllers/HotbarController/init.luau` (877 L) **[knit]**
  - HotbarController, :EquipToSlot(), :UnequipSlot(), :GetSelectedItem(), :GetSelectedSlot(), :IsToolSelected(), :IsMaterialSelected(), :GetSelectedToolId(), :WasPlaceButtonTapped(), :SetEnabled(), :RefreshInventory(), :KnitInit(), +21 more
- `src/ReplicatedStorage/Client/Controllers/BackpackController/WorkshopTab.luau` (883 L) **[<-1]**
  - WorkshopTab, :getPendingCrafts(), :fetchData(), :stopTimers(), :render(), :connectLiveUpdates(), local startCraftTimers(), local claimItem(), local craftItem(), local equipItem(), local unequipItem(), local deleteItem(), +1 more
- `scripts/codemap.py` (869 L)
  - demotion, is_git_repo, repo_name_for, list_files_git, _in_skip_dir, list_files_walk, enumerate_files, strip_comments, strip_lua_comments, luau_require_name, extract_lua_symbols, looks_like_component, +19 more
- `src/ReplicatedStorage/Shared/OrigamiBuilder.luau` (457 L) **[<-13]**
  - OrigamiBuilder, :BuildModel(), :ApplyAnimation()
- `src/ReplicatedStorage/Client/Controllers/EditController/init.luau` (706 L) **[knit]**
  - EditController, :Show(), :Hide(), :Toggle(), :IsActive(), :KnitInit(), :KnitStart(), local getCreatorController(), local screenToRay(), local rayPlaneIntersect(), local raycastGround(), local snapToGrid(), +17 more
- `src/ServerScriptService/Server/Services/OrigamiService.luau` (965 L) **[knit]**
  - OrigamiService, :GenerateModel(), :KnitInit(), :KnitStart(), local getApiUrl(), local getApiKey(), local checkRateLimit(), local _chargeForRequest()
- `src/ServerScriptService/Server/Services/WorkshopService.luau` (812 L) **[knit]**
  - WorkshopService, :KnitInit(), :KnitStart(), local _materialNamespace(), local findBodyPart(), local generateGUID(), local buildPrompt(), local removeEquippedVisuals(), local weldToBodyPart(), local applyCostume(), local removeCostume(), local reequipOnSpawn()
- `src/ReplicatedStorage/Client/Controllers/MiningController.luau` (646 L) **[knit]**
  - MiningController, :KnitInit(), :KnitStart(), local _getMouseRay(), local _raycastToBlock(), local _createHighlight(), local _updateHighlight(), local _updateCrackOverlay(), local _hideHighlight(), local _createTierBlockedUI(), local _showTierBlocked(), local _showBlockedMessage(), +7 more
- `src/ReplicatedStorage/Shared/TerrainBuilder.luau` (582 L)
  - TerrainBuilder, :Build(), local makePart(), local makeWedge(), local createBaseplate(), local createSpawnPlatform(), local createMountainRange(), local createCanyon(), local createWaterArea(), local createFloatingIslands(), local makePaperTree(), local createPaperForest(), +5 more
- `src/ReplicatedStorage/Client/Controllers/AnimatorController/init.luau` (587 L) **[knit]**
  - AnimatorController, :Toggle(), :Show(), :Hide(), :IsVisible(), :KnitInit(), :KnitStart(), local spawnMannequin(), local setStatus(), local updateSpawnButton(), local destroyMannequin(), local doSpawnMannequin(), +2 more
- `src/ReplicatedStorage/Shared/RegionConfig.luau` (146 L) **[<-9]**
  - RegionConfig, :formatSlotId(), :parseSlotId(), :getSlotCenter(), :getRegionAtPosition(), :getSlotMinChunk(), :worldChunkToLocal(), :localChunkToWorld(), :getRegionChunkSlot(), type SlotCenter
- `src/ReplicatedStorage/Shared/CreatureAI.luau` (597 L) **[<-4]**
  - CreatureAI, :Start(), type AnimPartData, local foldCurve(), local classifyPart(), local applyCreatureAnimation()
- `src/ReplicatedStorage/Client/Controllers/ReturnToBaseController.luau` (488 L) **[knit]**
  - ReturnToBaseController, :KnitInit(), :KnitStart(), local _now(), local _setFill(), local _setLabel(), local _setHint(), local _setBackground(), local _flashError(), local _disconnectChannelHooks(), local _cancelChannel(), local _isInOwnRegion(), +6 more
- `src/ServerScriptService/Server/Services/SpawnService.luau` (486 L) **[knit]**
  - SpawnService, :HandleReturnToBaseRequest(), :KnitInit(), :KnitStart(), type RtbResponse, local _placeOnPosition(), local placeOnPlatform(), local _computeRegionEdgePoint(), local _preSubscribeChunksAtPosition(), local _scheduleEdgeTeleport(), local _teleportOthersOutOfSlot(), local _ensureSlot(), +3 more
- `src/ReplicatedStorage/Shared/Enums/BlockType.luau` (219 L) **[<-12]**
  - type BlockType
- `src/ReplicatedStorage/Shared/FoldDemoData.luau` (832 L) **[<-2]**
  - FoldDemoData, :GetNames()
- `src/ServerScriptService/Server/Services/RegionContentService.luau` (463 L) **[knit]**
  - RegionContentService, :Load(), :GetContent(), :GetChunkDelta(), :Save(), :SetBlock(), :GetProps(), :AddProp(), :RemoveProp(), :Unload(), :FlushAll(), :KnitInit(), +11 more
- `src/ReplicatedStorage/Client/Controllers/ShopController/init.luau` (495 L) **[knit]**
  - ShopController, :Open(), :Close(), :Toggle(), :KnitInit(), :KnitStart(), :_buildUI(), :_selectCategory(), :_populateItems(), :_promptPurchase(), :_updateCurrencyDisplay(), :_refreshAllCurrencies(), +2 more
- `src/ReplicatedStorage/Client/Controllers/PlayController/init.luau` (528 L) **[knit]**
  - PlayController, :Activate(), :Cleanup(), :KnitInit(), :KnitStart(), local setStatus(), local updateCount(), local getPlacementCFrame(), local wireBehaviors(), local addNameLabel(), local clearAll(), local submitBuild(), +1 more
- `src/ServerScriptService/Server/Services/MonetizationService/init.luau` (431 L) **[knit]**
  - MonetizationService, :HasGamePass(), :PromptGamePass(), :PromptProduct(), :ConsumeProCreation(), :GrantProCreation(), :HasProCreation(), :GetLoginReward(), :ClaimLoginReward(), :IsPremium(), :GetPremiumMultiplier(), :HasModelSubscription(), +8 more
- `src/ReplicatedStorage/Client/Controllers/EmoteController/init.luau` (464 L) **[knit]**
  - EmoteController, :PlayPreset(), :PlayOnCharacter(), :KnitInit(), :KnitStart(), _playEmoteOnCharacter, local findMotor6D(), local lerpAngle(), local getJointRotation(), local makeCorner(), local setStatus(), local toggleWheel(), +2 more
- `src/ReplicatedStorage/Client/Controllers/WorldMapController.luau` (486 L) **[knit]**
  - WorldMapController, :Open(), :Close(), :Toggle(), :KnitInit(), :KnitStart(), type SlotOutline, local _worldToFrac(), local _createSlotOutline(), local _createUI(), local _refreshSlots(), local _onRender(), +1 more
- `src/ServerScriptService/Server/Services/PlayerDataService/init.luau` (384 L) **[knit]**
  - PlayerDataService, :WaitForProfile(), :ResetAndKick(), :RegisterService(), :ServiceFinished(), :KnitStart(), :KnitInit(), :Read(), :Write(), :_loadProfile(), :_loadPlayerProfiles(), type TableKeys, +9 more
- `src/ReplicatedStorage/Client/ClientEntry.server.luau` (8 L) **[ENTRY]**
- `src/ServerScriptService/Server/Main.server.luau` (4 L) **[ENTRY]**
- `src/ServerScriptService/Server/Services/MiningService.luau` (517 L) **[knit]**
  - MiningService, :KnitInit(), :KnitStart(), type MiningState, local _namespaceFor(), local _getPlayerTool(), local _getPlayerDistance(), local _awardDrops(), local _getBlockAtWorld(), local _tryTreeCollapse(), local _handleMineRequest()
- `src/ReplicatedStorage/Shared/MaterialTiers.luau` (113 L) **[<-8]**
  - MaterialTiers, :getRole(), :isBulk(), :isOre(), :getLayerForItem(), :getLayer(), type LayerTier
- `src/ReplicatedStorage/Shared/OrigamiUnfold.luau` (253 L) **[<-3]**
  - OrigamiUnfold, :Animate(), type Entry, local makePaperSheet(), local playFoldSound(), local collectParts(), local cacheEntries(), local computeStagger(), local applyScale(), local applyFlip(), local applyAccordion()
- `src/ReplicatedStorage/Client/Controllers/ModelLinkController/init.luau` (441 L) **[knit]**
  - ModelLinkController, :KnitStart(), :_setStatus(), :_renderLinkState(), :_refreshLinkState(), :_startStatusPoll(), :_buildPanel(), local fontBody(), local fontHeading(), local buttonHeight(), local make()
- `src/ReplicatedStorage/Client/Controllers/BreedingController/init.luau` (456 L) **[knit]**
  - BreedingController, :KnitInit(), :KnitStart(), :refreshEggs(), hatchEgg, local formatTime(), local spawnEggInWorld(), local clearEggs(), local startTimerLoop(), local startBreedProximityLoop()

