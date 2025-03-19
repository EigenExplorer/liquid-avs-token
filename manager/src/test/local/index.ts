import {
  testCreateStakerNodes,
  testDelegateNodes,
  testStakeAssetsToNodes,
  testStakeAssetsToNode,
  testUndelegateNodes,
} from "./tasks";

/**
 * Tests whether transaction proposals generated from tasks are exactly as intended
 * Run all tests with `npm run test` from the `/manager` folder
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
