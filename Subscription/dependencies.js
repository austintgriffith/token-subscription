const fs = require('fs');
module.exports = {
  'openzeppelin-solidity/contracts/ECRecovery.sol': fs.readFileSync('openzeppelin-solidity/contracts/ECRecovery.sol', 'utf8'),
  'openzeppelin-solidity/contracts/math/SafeMath.sol': fs.readFileSync('openzeppelin-solidity/contracts/math/SafeMath.sol', 'utf8'), 
  'openzeppelin-solidity/contracts/ownership/Ownable.sol': fs.readFileSync('openzeppelin-solidity/contracts/ownership/Ownable.sol', 'utf8'),
  'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol': fs.readFileSync('openzeppelin-solidity/contracts/token/ERC20/ERC20.sol', 'utf8'),
}
