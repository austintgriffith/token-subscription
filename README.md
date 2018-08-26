# ERC20 Subscription Service 

Using preapproved ERC20 tokens in combination with meta transactions to create reoccurring subscriptions on the Ethereum blockchain with as little burdon on the subscriber as possbile. 

## Abstract

A _publisher_ provides an ongoing service to multiple _subscribers_ and wishes to receive compensation on a periodic interval. The _publisher_ can deploy a lightweight _subscription contract_ to represent their service. Then, the _publisher_ sends _subscribers_ a link to terms which they sign as a single, off-chain meta transaction. This meta transaction is sent to the _publisher_ and/or a third party network that is otherwise incentivized. 

Immediately, and repeatedly after the agreed upon the period, the single meta transaction becomes valid using a timestamp or block number nonce (instead of a traditional replay attack nonce). The single, signed meta transaction can be submitted, proven valid through *ecrecover()*, and the *transferFrom()* of the pre-approved erc20 token from _subscriber_ to _publisher_ is executed. 

The _subscriber_ is in full control of the flow of tokens using the *approve()* function built into the ERC20 standard. They must pre-approve the _subscription contract_ that represents the service before any transfer can happen and they can revoke the allowance at any time to pause or cancel the subscription without touching the original meta transaction. Further, the terms of the subscription are explicitly signed in the meta transaction and can't be manipulated.

The _subscription contract_ also holds logic representing the subscription status for a given account so other smart contracts can verify on-chain that a _subscriber_ is actively paying the _publisher_.

Since this model works with any token that follows the *approve()* and *transferFrom()* standard, a stable token might serve as the best option for long running, monthly subscriptions. This shields both _publisher_ and _subscriber_ from price fluctuations.





