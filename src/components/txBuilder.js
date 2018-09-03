import React, { Component } from 'react';
import Blockies from 'react-blockies';
import deepmerge from 'deepmerge';
import { Blockie } from "dapparatus"
import axios from 'axios'


let defaultConfig = {}
defaultConfig.DEBUG = true;
defaultConfig.hide = true;
class TxBuilder extends Component {
  constructor(props) {
    super(props);
    let config = defaultConfig
    if(props.config) {
      config = deepmerge(config, props.config)
    }
    this.state = {
      config: config,
      contracts: {},
      encodeError:"",
      functionName:this.props.functionName
    }
  }
  loadContract(contractAddress){
    return new Promise((resolve, reject) => {
      let {require} = this.props
      let {DEBUG} = this.state.config
      let resultingContract
      try{
        if(!contractAddress) contractAddress="0x836a40ea2742d8154a5d50fccc4dc74a1dd3f823"//default to a token just in case

        if(DEBUG) console.log("TxBuilder - Loading Contract ABI for address JK HARDCODED FOR NOW ",contractAddress)

        axios.get("http://api-rinkeby.etherscan.io/api?module=contract&action=getabi&address="+contractAddress, { crossdomain: true })
        .catch((err)=>{
          console.log("Error getting gas price",err)
          reject(err)
        })
        .then((response)=>{
          if(response && response.data){
            console.log("ABI FROM API:",response.data)
            try{
              //console.log("ABI",response.data)
              let abi = JSON.parse(response.data.result)
              //console.log("CREATE CONTRACT",abi,contractAddress)
              let contract = new this.props.web3.eth.Contract(abi,contractAddress)
                resultingContract = contract.methods
                resultingContract._address = contractAddress
                resultingContract._abi = abi
                resultingContract._contract = contract
              resolve(resultingContract)
            }catch(e){
              console.log(e)
              console.log("Failed to load abi for ",contractAddress,"Let's try hitting the local url...")
              axios.get(this.props.backendUrl+"abi/"+contractAddress, { crossdomain: true })
              .catch((err)=>{
                console.log("Error getting gas price",err)
                reject(err)
              })
              .then((response)=>{
                if(response && response.data){
                  console.log("ABI FROM API:",response.data)
                  if(!response.data.result){
                    reject(response.data)
                  }
                  try{
                    let abi = JSON.parse(response.data.result)
                    //console.log("CREATE CONTRACT",abi,contractAddress)
                    let contract = new this.props.web3.eth.Contract(abi,contractAddress)
                      resultingContract = contract.methods
                      resultingContract._address = contractAddress
                      resultingContract._abi = abi
                      resultingContract._contract = contract
                      console.log("resolving with contract...")
                    resolve(resultingContract)
                  }catch(e){
                    console.log(e)
                    reject(e)
                  }
                }
              })
            }
          }
        })
      }catch(e){
        console.log("ERROR LOADING TXBUILDER CONTRACT",e)
        reject(e)
      }
    })
  }
  async componentDidMount(){
    try{
      let contract = await this.loadContract(this.props.contractAddress)
      if(contract){
        let writeFunctions = []
        for(let f in contract._abi){
          let fn = contract._abi[f]
          if(fn&&fn.type&&fn.type=="function"&&!fn.constant){
            writeFunctions.push(fn)
          }
        }
        this.setState({contract:contract,writeFunctions:writeFunctions},()=>{
          this.handleInput({target:{name:"forceLoad",value:true}})
        })

      }else{
        console.log("ERROR, NO CONTRACT LOADED FOR TX BUILDER")
        this.setState({failed:true})
      }
    }catch(e){
      console.log(e)
      this.setState({failed:true})
    }
  }
  handleInput(e){
    let update = {}
    update[e.target.name] = e.target.value
    this.setState(update,()=>{
      let thisFunction = false
      let functionNames = this.state.writeFunctions.map(fn => {
        if(this.state.functionName&& this.state.functionName==fn.name){
          thisFunction=fn
        }
      })
      let functionArguments = []
      let bytes = ""
      let argumentsReady = true
      let count = 1
      if(thisFunction){
        let inputForms = []
        for(let i in thisFunction.inputs){
          let input = thisFunction.inputs[i]
          let key = "input_"+input.name
          let thisValue = this.state[key]
          if(!thisValue){
            if(this.props["functionArg"+count]){
              thisValue=this.props["functionArg"+count]
            }
          }
          if(this.state[key+"adjust"]=="*10^18"){
            thisValue=thisValue*(10**18)
          }
          functionArguments.push(thisValue)
          if(!thisValue){
            argumentsReady=false
          }
          count++
        }
        if(argumentsReady){
          try{
            console.log("ENCODE TRANSACTION",thisFunction.name,functionArguments)
            bytes = this.state.contract[thisFunction.name](...functionArguments).encodeABI()
            if(this.state.bytes!=bytes){
              let update = {data:bytes,encodeError:""}
              this.setState(update)
              this.props.onUpdate(update)
            }
          }catch(e){
            this.setState({encodeError:e.toString()})
          }
        }
      }
    })
  }
  render(){
    if(!this.state || !this.state.contract){

      if(this.state.failed){
        return (
          <div style={{}}>
            (To address is not a Contract with source code available.)
          </div>
        )
      }

      return (
        <div style={{}}>
          loading contract...
        </div>
      )
    } else {
      if(!this.state.writeFunctions){
        return (
          <div>{"Is not a contract or contract doesn't have any write functions."}</div>
        )
      }
      //console.log(this.state.writeFunctions)
      let thisFunction = false
      let functionNames = this.state.writeFunctions.map(fn => {
        if(this.state.functionName&& this.state.functionName==fn.name){
          thisFunction=fn
        }
        return (
          <option key={fn.name} value={fn.name}>{fn.name}</option>
        )
      })
      let functionArguments = []
      let inputs = ""
      let bytes = ""
      let count = 1
      if(thisFunction){
        let inputForms = []
        for(let i in thisFunction.inputs){
          let input = thisFunction.inputs[i]
          let key = "input_"+input.name
          let thisValue = this.state[key]
          if(!thisValue){
            if(this.props["functionArg"+count]){
              thisValue=this.props["functionArg"+count]
            }
          }

          functionArguments.push(thisValue)

          let extra = ""
          if(input.type=="uint256"){
            extra = (
              <button onClick={()=>{
                this.handleInput({target:{name:key,value:this.state[key]*10**18}})
              }}>{"*10^18"}</button>
            )
          }else if(input.type=="bytes32"){
            extra = (
              <button onClick={()=>{
                this.handleInput({target:{name:key,value:this.props.web3.utils.toHex(this.state[key])}})
              }}>{"hex"}</button>
            )
          }else if(input.type=="address"&&this.state[key]){
            extra = (
              <Blockie address={this.state[key].toLowerCase()}/>
            )
          }
          inputForms.push(
            <div key={key}>{input.name}:<input
                style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                type="text" name={key} value={thisValue} onChange={this.handleInput.bind(this)}
            />{extra}({input.type})</div>
          )
          count++
        }
        if(inputForms&&inputForms.length>0){
          inputs = (
            <div>
              {inputForms}
            </div>
          )
        }
      }
      let errorObj = ""
      if(this.state.encodeError){
        errorObj = (
          <div style={{margin:5,border:"1px solid #88555",backgroundColor:"#492929",fontSize:14,padding:5}}>
            {this.state.encodeError}
          </div>
        )
      }
      return (
        <div style={{}}>
          Function <select name="functionName" value={this.state.functionName} onChange={this.handleInput.bind(this)} >
            <option key="none" value=""></option>
            {functionNames}
          </select>
          {inputs}
          {errorObj}
        </div>
      )
    }
  }
}
export default TxBuilder;
