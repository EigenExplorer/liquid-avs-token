import {
  testCreateStakerNodes,
  testDelegateNodes,
  testStakeAssetsToNodes,
  testStakeAssetsToNode,
  testUndelegateNodes,
  testAddToken,
  testPauseLiquidToken,
  testRemoveToken,
  testSetMaxNodes,
  testSetVolatilityThreshold,
  testUnpauseLiquidToken,
  testUpgradeStakerNodeImplementation,
} from "./tasks";

/**
 * Tests whether transaction proposals generated from tasks are exactly as intended
 *
 */
async function testAllTasks() {
  // Manager Tasks
  await testCreateStakerNodes();
  await testDelegateNodes();
  await testStakeAssetsToNodes();
  await testStakeAssetsToNode();
  await testUndelegateNodes();

  // System Tasks
  await testAddToken();
  await testPauseLiquidToken();
  await testRemoveToken();
  await testSetMaxNodes();
  await testSetVolatilityThreshold();
  await testUnpauseLiquidToken();
  await testUpgradeStakerNodeImplementation();
}

await testAllTasks();
