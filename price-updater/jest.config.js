module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  transform: {
    '^.+\\.tsx?$': [
      'ts-jest',
      {
        isolatedModules: true,
        diagnostics: false
      }
    ]
  },
  moduleNameMapper: {
    '^node:http$': 'http'
  },
  transformIgnorePatterns: [
    '/node_modules/(?!(web3|node-fetch))'
  ],
  setupFilesAfterEnv: ['./jest.setup.ts'],
  testMatch: ['**/*.test.ts'], // Add this line
};