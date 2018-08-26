pragma solidity ^0.4.24;

/*
  Token Subscriptions on the Blockchain

  WIP POC simplified version of  EIP-1337 / ERC-948

  Austin Thomas Griffith - https://austingriffith.com

  Building on previous works:
  https://gist.github.com/androolloyd/0a62ef48887be00a5eff5c17f2be849a
  https://media.consensys.net/subscription-services-on-the-blockchain-erc-948-6ef64b083a36
  https://medium.com/gitcoin/technical-deep-dive-architecture-choices-for-subscriptions-on-the-blockchain-erc948-5fae89cabc7a
  https://github.com/ethereum/EIPs/pull/1337
  https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1077.md
  https://github.com/gnosis/safe-contracts

  Earlier Meta Transaction Demo:
  https://github.com/austintgriffith/bouncer-proxy

  Huge thanks to, as always, to OpenZeppelin for the rad contracts:
*/

import "openzeppelin-solidity/contracts/ECRecovery.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract Subscription is Ownable{
  using ECRecovery for bytes32;

  constructor() public { }

  //contract will need to hold funds to pay gas 
  // copied from https://github.com/uport-project/uport-identity/blob/develop/contracts/Proxy.sol
  function () payable { emit Received(msg.sender, msg.value); }
  event Received (address indexed sender, uint value);

  //similar to a nonce that avoids replay attacks this allows a single execution
  // every x seconds for a given subscription
  //   subscriptionHash  => next valid block number
  mapping(bytes32 => uint) public nextValidTimestamp;

  //for some cases of delegated execution, this contract will pay a third party
  // to execute the transfer. If this happens, the owner of this contract must
  // sign the subscriptionHash
  mapping(bytes32 => bool) public publisherSigned;

  //only the owner of this contract can sign the subscriptionHash to whitelist
  // a specific subscription to start rewarding the relayers for paying the
  // gas of the transactions out of the balance of this contract
  function signSubscriptionHash(bytes32 subscriptionHash) public onlyOwner returns(bool) {
    publisherSigned[subscriptionHash]=true;
    return true;
  }

  //this is used by external smart contracts to verify on-chain that a
  // particular subscription is "paid" and "active"
  // there must be a small grace period added to allow the publisher
  // or desktop miner to execute
  function isSubscriptionActive(bytes32 subscriptionHash,uint gracePeriodSeconds) external view returns (bool) {
    return (block.timestamp >= nextValidTimestamp[subscriptionHash]+gracePeriodSeconds);
  }

  //given the subscription details, generate a hash and try to kind of follow
  // the eip-191 standard and eip-1077 standard from my dude @avsa
  function getSubscriptionHash(
    address from, //the subscriber
    address to, //the publisher
    address tokenAddress, //the token address paid to the publisher
    uint256 tokenAmount, //the token amount paid to the publisher
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer //the address that will pay the tokens to the relayer
  )
     public
     view
     returns (bytes32)
  {
     return keccak256(abi.encodePacked(byte(0x19),byte(0),address(this),from,to,tokenAddress,tokenAmount,periodSeconds,gasToken,gasPrice,gasPayer));
  }

  //ecrecover the signer from hash and the signature
  function getSubscriptionSigner(
    bytes32 subscriptionHash, //hash of subscription
    bytes signature //proof the subscriber signed the meta trasaction
  )
    public
    pure
    returns (address)
  {
    return subscriptionHash.toEthSignedMessageHash().recover(signature);
  }

  //check if a subscription is signed correctly and the timestamp is ready for
  // the next execution to happen
  function isSubscriptionReady(
    address from, //the subscriber
    address to, //the publisher
    address tokenAddress, //the token address paid to the publisher
    uint256 tokenAmount, //the token amount paid to the publisher
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer, //the address that will pay the tokens to the relayer
    bytes signature //proof the subscriber signed the meta trasaction
  )
    public
    view
    returns (bool)
  {
    bytes32 subscriptionHash = getSubscriptionHash(from,to,tokenAddress,tokenAmount,periodSeconds,gasToken,gasPrice,gasPayer);
    address signer = getSubscriptionSigner(subscriptionHash,signature);
    uint allowance = (ERC20(tokenAddress)).allowance(from,address(this));
    return (signer==from && block.timestamp>=nextValidTimestamp[subscriptionHash] && allowance>=tokenAmount);
  }

  //you don't really need this if you are using the approve/transferFrom method
  // because you control the flow of tokens by approving this contract address,
  // but to make the contract an extensible examplefor later user I'll add this
  function cancelSubscription(
    address from, //the subscriber
    address to, //the publisher
    address tokenAddress, //the token address paid to the publisher
    uint256 tokenAmount, //the token amount paid to the publisher
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer, //the address that will pay the tokens to the relayer
    bytes signature //proof the subscriber signed the meta trasaction
  )
  public
  returns (
    bool success
  ){
    bytes32 subscriptionHash = getSubscriptionHash(from,to,tokenAddress,tokenAmount,periodSeconds,gasToken,gasPrice,gasPayer);
    address signer = subscriptionHash.toEthSignedMessageHash().recover(signature);
    //the signature must be valid
    require(signer==from,"Invalid Signature");
    //underflow nextValidTimestamp for this subscriptionHash
    nextValidTimestamp[subscriptionHash]=0;
    nextValidTimestamp[subscriptionHash]=nextValidTimestamp[subscriptionHash]-1;
    //at this point the nextValidTimestamp should be a timestamp that will never
    //be reached during the brief window human existence
    return true;
  }

  //execute the transferFrom to pay the publisher from the subscriber
  // the subscriber has full control by approving this contract an allowance
  function executeSubscription(
    address from, //the subscriber
    address to, //the publisher
    address tokenAddress, //the token address paid to the publisher
    uint256 tokenAmount, //the token amount paid to the publisher
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer, //the address that will pay the tokens to the relayer
    bytes signature //proof the subscriber signed the meta trasaction
  )
  public
  returns (
    bool success
  ){
    //make sure the subscription is valid and ready
    // pulled this out so I have the hash, should be exact code as "isSubscriptionReady"
    bytes32 subscriptionHash = getSubscriptionHash(from,to,tokenAddress,tokenAmount,periodSeconds,gasToken,gasPrice,gasPayer);
    address signer = getSubscriptionSigner(subscriptionHash,signature);

    //the signature must be valid
    require(signer==from,"Invalid Signature");
    //timestamp must be equal to or past the next period
    require(block.timestamp>=nextValidTimestamp[subscriptionHash],"Subscription is not ready");

    //increment the next valid period time
    if(nextValidTimestamp[subscriptionHash]<=0){
      //if this is the very first, start from the current time
      nextValidTimestamp[subscriptionHash]=block.timestamp+periodSeconds;
    }else{
      nextValidTimestamp[subscriptionHash]=nextValidTimestamp[subscriptionHash]+periodSeconds;
    }

    //it is possible for the subscription execution to be run by a third party
    // incentivized in the terms of the subscription with a gasToken and gasPrice
    // pay that out now...
    if(gasPrice>0){
      if(gasToken==address(0)){
        //this is an interesting case where the service will pay the third party
        // ethereum out of the subscription contract itself
        // for this to work the publisher must send ethereum to the contract
        require(publisherSigned[subscriptionHash],"Publisher has not signed this subscriptionHash");
        require(msg.sender.call.value(gasPrice).gas(36000)(),"Subscription contract failed to pay ether to relayer");
      }else if(gasPayer==address(this)||gasPayer==address(0)){
        //in this case, this contract will pay a token to the relayer to
        // incentivize them to pay the gas for the meta transaction
        // for security, the publisher must have signed the subscriptionHash
        require(publisherSigned[subscriptionHash],"Publisher has not signed this subscriptionHash");
        require((ERC20(gasToken)).transfer(msg.sender,gasPrice),"Failed to pay gas as contract");
      }else if(gasPayer==to){
        //in this case the relayer is paid with a token from the publisher
        // the publisher must have approved this contract AND signed the
        // subscriptionHash for this to work
        require(publisherSigned[subscriptionHash],"Publisher has not signed this subscriptionHash");
        require((ERC20(gasToken)).transferFrom(to,msg.sender,gasPrice),"Failed to pay gas as to account");
      }else if(gasPayer==from){
        //in this case the relayer is paid with a token from the subscriber
        // this works best if it is the same token being transferred to the
        // publisher because it is already in the allowance
        require((ERC20(gasToken)).transferFrom(from,msg.sender,gasPrice),"Failed to pay gas as from account");
      }else{
        //the subscriber could craft the gasPayer to be a fellow subscriber that
        // that has approved this contract to move tokens and then exploit that
        // don't allow that...
        require(false,"The gasPayer is invalid");
        //on the other hand it might be really cool to allow *any* account to
        // pay the third party as long as they have approved this contract
        // AND the publisher has signed off on it. The downside would be a
        // publisher not paying attention and signs a subscription that attacks
        // a different subscriber
      }
    }

    //finally, let make the transfer from the subscriber to the publisher
    // that's what all of this is for, this one little line:
    require((ERC20(tokenAddress)).transferFrom(from,to,tokenAmount));

    emit ExecuteSubscription(from,to,tokenAddress,tokenAmount,periodSeconds,gasToken,gasPrice,gasPayer);
    return true;
  }

  event ExecuteSubscription(
    address indexed from, //the subscriber
    address indexed to, //the publisher
    address tokenAddress, //the token address paid to the publisher
    uint256 tokenAmount, //the token amount paid to the publisher
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer //the address that will pay the tokens to the relayer
  );

}
