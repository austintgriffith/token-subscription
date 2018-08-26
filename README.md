# 💰🕰️📋 EIP 1337 POC - Token Subscriptions on Ethereum

Subscribers sign a single off-chain meta transaction that is periodically resubmitted to the blockchain to create a trustless set-it-and-forget-it subscription model on Ethereum. 

[https://github.com/ethereum/EIPs/pull/1337](https://github.com/ethereum/EIPs/pull/1337)

## Demo

[![screencast.png](https://user-images.githubusercontent.com/2653167/44634126-7a5b0d00-a952-11e8-85fd-16e66a36ad07.png)](https://youtu.be/_znjpTRGCbs)

[https://sub.metatx.io](https://sub.metatx.io)

## Abstract

A _publisher_ provides an ongoing service to multiple _subscribers_ and wishes to receive compensation on a periodic interval. The _publisher_ can deploy a lightweight _subscription contract_ to represent their service. Then, the _publisher_ sends _subscribers_ a link to terms which they sign as a single, off-chain meta transaction. This meta transaction is sent to the _publisher_ and/or a third party network that is incentivized with a _gasToken_. 

Immediately, and repeatedly after the agreed upon the period, the single meta transaction becomes valid using a timestamp or block number nonce (instead of a traditional replay attack nonce). The single, signed meta transaction can be submitted, proven valid through *ecrecover()*, and the *transferFrom()* of the pre-approved erc20 token from _subscriber_ to _publisher_ is executed. 

The _subscriber_ is in full control of the flow of tokens using the *approve()* function built into the ERC20 standard. They must pre-approve the _subscription contract_ that represents the service before any transfer can happen and they can revoke the allowance at any time to pause or cancel the subscription without touching the original meta transaction. Further, the terms of the subscription are explicitly signed in the meta transaction and can't be manipulated.

The _subscription contract_ also holds logic representing the subscription status for a given account so other smart contracts can verify on-chain that a _subscriber_ is actively paying the _publisher_.

Since this model works with any token that follows the *approve()* and *transferFrom()* standard, a stable token might serve as the best option for long running, monthly subscriptions. This shields both _publisher_ and _subscriber_ from price fluctuations.

Meta transactions can be submitted by any relayer and the relayer can be incentivized with a _gasToken_. This token can be paid by the _publisher_, the _subscriber_, or the _subscription contract_. The _subscription contract_ can also reimburse the relayers directly with Ethereum. If funds are to be paid from the _subscription contract_, the _subscriptionHash_ must be signed by the _publisher_. 


```
 ██╗██████╗ ██████╗ ███████╗
███║╚════██╗╚════██╗╚════██║
╚██║ █████╔╝ █████╔╝    ██╔╝
 ██║ ╚═══██╗ ╚═══██╗   ██╔╝ 
 ██║██████╔╝██████╔╝   ██║  
 ╚═╝╚═════╝ ╚═════╝    ╚═╝  -EIP-
 ```
                            
(All your blockchain subscriptions are belong to us)
