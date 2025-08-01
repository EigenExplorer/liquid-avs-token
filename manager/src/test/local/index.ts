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
    testBatchUpdateRates,
    testUpdateAllPricesIfNeeded,
    testGrantRole,
    testRevokeRole,
    testSetPriceUpdateInterval,
    testDisableEmergencyInterval
} from './tasks'

/**
 * Tests whether transaction proposals generated from tasks are exactly as intended
 * Run all tests with `npm run test` from the `/manager` folder
 *
 */
async function testAllTasks() {
    try {
        // Manager Tasks
        await testCreateStakerNodes()
        await testDelegateNodes()
        await testStakeAssetsToNodes()
        await testStakeAssetsToNode()
        await testUndelegateNodes()

        // System Tasks
        await testAddToken()
        await testPauseLiquidToken()
        await testRemoveToken()
        await testSetMaxNodes()
        await testSetVolatilityThreshold()
        await testUnpauseLiquidToken()
        await testUpgradeStakerNodeImplementation()
        await testUpdateAllPricesIfNeeded()
        await testBatchUpdateRates()
        await testGrantRole()
        await testRevokeRole()
        await testSetPriceUpdateInterval()
        await testDisableEmergencyInterval()
    } catch {}
}

await testAllTasks()
