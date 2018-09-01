pragma solidity ^0.4.24;

/*

  This is just an example token to test out token subscriptions

 */

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";


contract SomeStableToken is ERC20Mintable {

  string public name = "SomeStableToken";
  string public symbol = "SST";
  uint8 public decimals = 18;

  constructor() public { }

}
