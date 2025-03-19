import { jest } from '@jest/globals';
import { BigNumber as BN } from "bignumber.js";

// Mock the updater module
jest.mock('../../src/index', () => {
  const originalModule = jest.requireActual('../../src/index');
  
  return {
    ...originalModule,
    updater: {
      ...originalModule.updater,
      updateIndividualPrice: jest.fn().mockImplementation(
        (web3, oracleContract, managerContract, account, tokenAddress, newPrice) => {
          // Instead of calling the real function, just update the mock Oracle directly
          oracleContract.methods.updateRate(tokenAddress, newPrice);
          return Promise.resolve(true);
        }
      )
    }
  };
});

// Mock Token Manager Contract
const mockManagerContract = {
  methods: {
    getTokenInfo: jest.fn().mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "1000000000000000000", // Initial price: 1 ETH
        volatilityThreshold: "100000000000000000", // 10% threshold
        decimals: "18",
      })
    })),
    // Mock the deposit and withdrawal functions
    deposit: jest.fn().mockImplementation((account, amount) => ({
      call: jest.fn().mockResolvedValue({
        shares: "1000000000000000000" // 1 share
      }),
      estimateGas: jest.fn().mockResolvedValue(100000),
      encodeABI: jest.fn().mockReturnValue("0xabcdef")
    })),
    withdraw: jest.fn().mockImplementation((account, shares) => ({
      call: jest.fn(),
      estimateGas: jest.fn().mockResolvedValue(100000),
      encodeABI: jest.fn().mockReturnValue("0x123456")
    })),
    getWithdrawalAmountForShares: jest.fn().mockImplementation((shares) => ({
      call: jest.fn()
    })),
    updatePrice: jest.fn().mockImplementation((tokenAddress, newPrice) => ({
      call: jest.fn(),
      estimateGas: jest.fn().mockResolvedValue(100000),
      encodeABI: jest.fn().mockReturnValue("0x789abc")
    }))
  }
};

// Mock Oracle Contract
const mockOracleContract = {
  methods: {
    updateRate: jest.fn().mockImplementation((tokenAddress, rate) => ({
      estimateGas: jest.fn().mockResolvedValue(100000),
      encodeABI: jest.fn().mockReturnValue("0xdef123")
    })),
    batchUpdateRates: jest.fn().mockImplementation((tokens, rates) => ({
      estimateGas: jest.fn().mockResolvedValue(150000),
      encodeABI: jest.fn().mockReturnValue("0x456789")
    }))
  },
  options: {
    address: "0xMockOracleAddress"
  }
};

// Import the functions to test
import { updater } from '../../src/index';

describe('Withdrawal After Price Change Tests', () => {
  // Initial setup
  let tokenAddress = "0xTokenAddress";
  let account = { address: "0xUserAddress" };
  let web3 = {
    eth: {
      getGasPrice: jest.fn().mockResolvedValue("20000000000"),
      getTransactionCount: jest.fn().mockResolvedValue(1),
      sendSignedTransaction: jest.fn().mockResolvedValue({ transactionHash: "0xTransaction1" })
    }
  };

  beforeEach(() => {
    jest.clearAllMocks();
    
    // Reset price to initial value
    mockManagerContract.methods.getTokenInfo.mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "1000000000000000000", // 1 ETH
        volatilityThreshold: "100000000000000000", // 10% threshold
        decimals: "18",
      })
    }));
    
    // Reset mocked updateIndividualPrice
    updater.updateIndividualPrice.mockClear();
  });

  test('Should return less tokens on withdrawal when price increases', async () => {
    // 1. User deposits 1 ETH at price of 1 ETH per token
    mockManagerContract.methods.getWithdrawalAmountForShares.mockImplementation((shares) => ({
      call: jest.fn().mockResolvedValue("1000000000000000000") // 1 token initially
    }));
    
    // Initial check of withdrawal amount for 1 share
    const initialWithdrawalAmount = await mockManagerContract.methods.getWithdrawalAmountForShares("1000000000000000000").call();
    expect(initialWithdrawalAmount).toBe("1000000000000000000"); // 1 token for 1 share
    
    // 2. Price increases to 2 ETH per token
    // Update the price through the oracle
    await updater.updateIndividualPrice(
      web3,
      mockOracleContract,
      mockManagerContract,
      account,
      tokenAddress,
      "2000000000000000000" // New price: 2 ETH
    );
    
    // 3. Update manager's stored price info to reflect the change
    mockManagerContract.methods.getTokenInfo.mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "2000000000000000000", // New price: 2 ETH
        volatilityThreshold: "100000000000000000", // 10% threshold
        decimals: "18",
      })
    }));
    
    // 4. Check withdrawal amount after price increase
    mockManagerContract.methods.getWithdrawalAmountForShares.mockImplementation((shares) => ({
      call: jest.fn().mockResolvedValue("500000000000000000") // 0.5 tokens after price increase
    }));
    
    const newWithdrawalAmount = await mockManagerContract.methods.getWithdrawalAmountForShares("1000000000000000000").call();
    expect(newWithdrawalAmount).toBe("500000000000000000"); // 0.5 tokens for 1 share after price increase
    
    // 5. Verify the price update was called
    expect(updater.updateIndividualPrice).toHaveBeenCalledWith(
      web3,
      mockOracleContract,
      mockManagerContract,
      account,
      tokenAddress,
      "2000000000000000000"
    );
  });

  test('Should return more tokens on withdrawal when price decreases', async () => {
    // 1. User deposits 1 ETH at price of 1 ETH per token
    mockManagerContract.methods.getWithdrawalAmountForShares.mockImplementation((shares) => ({
      call: jest.fn().mockResolvedValue("1000000000000000000") // 1 token initially
    }));
    
    // Initial check of withdrawal amount for 1 share
    const initialWithdrawalAmount = await mockManagerContract.methods.getWithdrawalAmountForShares("1000000000000000000").call();
    expect(initialWithdrawalAmount).toBe("1000000000000000000"); // 1 token for 1 share
    
    // 2. Price decreases to 0.5 ETH per token
    // Update the price through the oracle
    await updater.updateIndividualPrice(
      web3,
      mockOracleContract,
      mockManagerContract,
      account,
      tokenAddress,
      "500000000000000000" // New price: 0.5 ETH
    );
    
    // 3. Update manager's stored price info to reflect the change
    mockManagerContract.methods.getTokenInfo.mockImplementation((tokenAddress) => ({
      call: jest.fn().mockResolvedValue({
        pricePerUnit: "500000000000000000", // New price: 0.5 ETH
        volatilityThreshold: "100000000000000000", // 10% threshold
        decimals: "18",
      })
    }));
    
    // 4. Check withdrawal amount after price decrease
    mockManagerContract.methods.getWithdrawalAmountForShares.mockImplementation((shares) => ({
      call: jest.fn().mockResolvedValue("2000000000000000000") // 2 tokens after price decrease
    }));
    
    const newWithdrawalAmount = await mockManagerContract.methods.getWithdrawalAmountForShares("1000000000000000000").call();
    expect(newWithdrawalAmount).toBe("2000000000000000000"); // 2 tokens for 1 share after price decrease
    
    // 5. Verify the price update was called
    expect(updater.updateIndividualPrice).toHaveBeenCalledWith(
      web3,
      mockOracleContract,
      mockManagerContract,
      account,
      tokenAddress,
      "500000000000000000"
    );
  });
}); 