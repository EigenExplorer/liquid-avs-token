# Liquid Staking Protocol

## Overview

This document outlines the architecture of a liquid staking protocol, which allows users to stake their tokens while maintaining liquidity through the issuance of liquid staking tokens.

## Components

### IAvsToken

The main entry point for users to interact with the protocol.

- **Deposit Token**: Users can deposit their tokens and receive liquid tokens in return.
- **Receive Liquid Token**: Users receive liquid tokens representing their stake.
- **Unstake**: Users can initiate the unstaking process to reclaim their original tokens.

### Withdrawal Router

Manages the withdrawal process for users.

- **Claim Token**: After the withdrawal delay, users can claim their unstaked tokens.

### Liquid AVS Token Manager

Central component managing the liquid staking tokens and interactions with staker nodes.

- **Retrieve Assets**: Manages the assets deposited by users.
- **Retrieve Assets via Token Contract**: Interacts with the underlying token contracts.

### Reward Router

Handles the distribution of staking rewards.

- **Enable funds to withdraw**: Allows users to withdraw their rewards through the Withdrawal Router.

### Staker Nodes

Multiple staker nodes that perform the actual staking on the network.

- **Transfer EL Rewards**: Earnings from staking are transferred to the Reward Router.

### Eigenlayer (Delegation Manager)

Manages the delegation of stakes to the protocol.

- **Delegate & Deposit**: Staker nodes delegate and deposit stakes to the Eigenlayer.

### EE Re-staking Manager

Manages the re-staking process for increased efficiency.

- **Retrieve Assets**: Interacts with the Liquid AVS Token Manager to retrieve and manage assets.

## User Flow

1. Users deposit tokens into the IAvsToken contract.
2. They receive liquid tokens in return, maintaining liquidity while staking.
3. The Liquid AVS Token Manager distributes the staked assets among Staker Nodes.
4. Staker Nodes delegate and deposit to the Eigenlayer.
5. Rewards are collected by the Reward Router.
6. Users can unstake through the IAvsToken contract.
7. After a delay, users can claim their tokens via the Withdrawal Router.

## Key Features

- Liquid staking: Users maintain liquidity while earning staking rewards.
- Distributed staking: Multiple Staker Nodes for increased security and decentralization.
- Reward distribution: Automated reward collection and distribution.
- Managed withdrawals: Controlled withdrawal process to ensure protocol stability.

## Security Considerations

- Implement proper access controls for critical functions.
- Ensure secure handling of user deposits and withdrawals.
- Implement slashing protection mechanisms.
- Regular audits of smart contracts, especially the IAvsToken and Liquid AVS Token Manager.

## Future Improvements

- Implement a governance mechanism for protocol upgrades.
- Explore cross-chain liquid staking possibilities.
- Optimize gas efficiency for large-scale operations.