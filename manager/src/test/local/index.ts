import {
  testCreateStakerNodes,
  testDelegateNodes,
  testStakeAssetsToNodes,
  testStakeAssetsToNode,
  testUndelegateNodes,
} from "./tasks";

/**
 * Tests whether transaction proposals generated from tasks are exactly as intended
 *
 */
async function testAllTasks() {
  await testCreateStakerNodes();
  await testDelegateNodes();
  await testStakeAssetsToNodes();
  await testStakeAssetsToNode();
  await testUndelegateNodes();
}

await testAllTasks();
