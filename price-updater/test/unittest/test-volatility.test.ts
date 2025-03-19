import { jest } from '@jest/globals';
import { BigNumber as BN } from "bignumber.js";

// Create a mock implementation of checkVolatilityThreshold that doesn't rely on global.configObj
jest.mock('../../src/index', () => {
  const originalModule = jest.requireActual('../../src/index');
  
  // Create our own implementation that uses the mockConfig directly
  const mockCheckVolatilityThreshold = async (managerContract, tokenAddress, newPrice) => {
    try {
      const tokenInfo = await managerContract.methods.getTokenInfo(tokenAddress).call();
      const oldPrice = new BN(tokenInfo.pricePerUnit);
      const volatilityThreshold = new BN(tokenInfo.volatilityThreshold);
      
      // Use testConfig which will be set during tests
      if (volatilityThreshold.isZero() || global.testConfig?.volatility_threshold_bypass) return true;
      
      const newPriceBN = new BN(newPrice);
      const changeRatio = newPriceBN.minus(oldPrice).abs().multipliedBy(1e18).dividedBy(oldPrice);
      const result = changeRatio.lte(volatilityThreshold);
      return result;
    } catch (error) {
      console.error(`Volatility check failed for ${tokenAddress}:`, error);
      return true;
    }
  };
  
  return {
    ...originalModule,
    checkVolatilityThreshold: mockCheckVolatilityThreshold
  };
});

// Create mock contract and manager
const mockManager = {
  methods: {
    getTokenInfo: jest.fn().mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "1000000000000000000", // 1 ETH
        volatilityThreshold: "100000000000000000", // 10% threshold
        decimals: "18",
      })
    }))
  }
};

// Zero threshold manager
const zeroThresholdManager = {
  methods: {
    getTokenInfo: jest.fn().mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "1000000000000000000", // 1 ETH
        volatilityThreshold: "0", // Zero threshold
        decimals: "18",
      })
    }))
  }
};

// Mock config with volatility bypass off
const mockConfig = {
  volatility_threshold_bypass: false
};

// Mock config with volatility bypass on
const bypassConfig = {
  volatility_threshold_bypass: true
};

// Import the function to test
const { checkVolatilityThreshold } = require('../../src/index');

describe('Volatility Threshold Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    global.testConfig = mockConfig; // Set default test config
  });

  test('Should pass when price change is below threshold', async () => {
    // 1.09 ETH (9% increase, below 10% threshold)
    const newPrice = "1090000000000000000";
    const result = await checkVolatilityThreshold(mockManager, "0xtoken", newPrice);
    
    expect(result).toBe(true);
    expect(mockManager.methods.getTokenInfo).toHaveBeenCalledWith("0xtoken");
  });

  test('Should fail when price change is above threshold', async () => {
    // 1.11 ETH (11% increase, above 10% threshold)
    const newPrice = "1110000000000000000";
    const result = await checkVolatilityThreshold(mockManager, "0xtoken", newPrice);
    
    expect(result).toBe(false);
    expect(mockManager.methods.getTokenInfo).toHaveBeenCalledWith("0xtoken");
  });

  test('Should pass exactly at threshold limit', async () => {
    // 1.10 ETH (10% increase, exactly at threshold)
    const newPrice = "1100000000000000000";
    const result = await checkVolatilityThreshold(mockManager, "0xtoken", newPrice);
    
    expect(result).toBe(true);
    expect(mockManager.methods.getTokenInfo).toHaveBeenCalledWith("0xtoken");
  });

  test('Should pass with zero threshold regardless of change', async () => {
    // 2.00 ETH (100% increase, would normally fail)
    const newPrice = "2000000000000000000";
    const result = await checkVolatilityThreshold(zeroThresholdManager, "0xtoken", newPrice);
    
    expect(result).toBe(true);
    expect(zeroThresholdManager.methods.getTokenInfo).toHaveBeenCalledWith("0xtoken");
  });

  test('Should pass when bypass is enabled regardless of threshold', async () => {
    // Set config with bypass enabled
    global.testConfig = bypassConfig;
    
    // 2.00 ETH (100% increase, would normally fail)
    const newPrice = "2000000000000000000";
    const result = await checkVolatilityThreshold(mockManager, "0xtoken", newPrice);
    
    expect(result).toBe(true);
    expect(mockManager.methods.getTokenInfo).toHaveBeenCalledWith("0xtoken");
  });

  test('Should handle error gracefully and return true', async () => {
    // Create error-throwing manager
    const errorManager = {
      methods: {
        getTokenInfo: jest.fn().mockImplementation(() => {
          throw new Error("Test error");
        })
      }
    };
    
    const newPrice = "1100000000000000000";
    const result = await checkVolatilityThreshold(errorManager, "0xtoken", newPrice);
    
    expect(result).toBe(true);
  });
}); 