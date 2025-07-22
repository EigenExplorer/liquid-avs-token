# Liquid AVS Token

Liquid AVS Token (LAT) is a new asset class within the restaking ecosystem. LAT allows you to hold (re)staked tokens in liquid form while directly supporting specific Autonomous Verifiable Services (AVSs). LAT is part of the Direct Liquid Staking framework.

## Getting Started

## Basics

- [Direct Liquid Staking](https://docs.area.club/concepts/direct-liquid-restaking)
- [Liquid AVS Token](https://docs.area.club/concepts/lat)
- [Why LAT?](https://docs.area.club/guides/why-lat)
- [What LATs Are and Are Not](https://docs.area.club/guides/comparison)

## Branching

The main branches we use are:

- [`dev (default)`](https://github.com/EigenExplorer/liquid-avs-token/tree/dev): The most up-to-date branch, containing the work-in-progress code for upcoming releases
- [`testnet-holesky`](https://github.com/EigenExplorer/liquid-avs-token/tree/testnet-holesky): Our current testnet deployment
- [`main`](https://github.com/EigenExplorer/liquid-avs-token/tree/main): Our current Ethereum mainnet deloyment

## Technical Documentation

- [LAT contracts, backend and API](https://docs.area.club/developers/introduction)
- [EigenExplorer API](https://docs.eigenexplorer.com/api-reference/introduction)

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project and run tests with these commands:

```
foundryup

make build
make tests
```

## Deployments

- [Holesky Deployments](https://github.com/EigenExplorer/lat-deployments/tree/main/holesky)
- [Mainnet Deployments](https://github.com/EigenExplorer/lat-deployments/tree/main/mainnet)
