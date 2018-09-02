import React, { Component } from 'react';
import './App.css';
import { Metamask, Gas, ContractLoader, Transactions, Events, Scaler, Blockie, Address, Button } from "dapparatus"
import Web3 from 'web3';
import queryString from 'query-string';
import axios from 'axios';
import Miner from './components/miner.js';
import TxBuilder from './components/txBuilder.js';
import Subscriptions from './components/subscriptions.js';
let backendUrl = "http://localhost:10002/"
console.log("window.location:",window.location)
/*if(window.location.href.indexOf("metatx.io")>=0)
{
  backendUrl = "http://stage.metatx.io:10001/"
}else */if(window.location.href.indexOf("metatx.io")>=0)
{
  backendUrl = "https://subbackend.metatx.io/"
}

class App extends Component {
  constructor(props) {
    super(props);
    const getParams = queryString.parse(window.location.search)

    let timeAmount = getParams.timeAmount || 1
    let timeType = getParams.timeType || "months"

    this.state = {
      web3: false,
      account: false,
      gwei: 4,
      doingTransaction: false,
      subscriptionContract: false,
      customTokenContract: false,
      toAddress: getParams.toAddress,
      timeAmount: timeAmount,
      timeType: timeType,
      data: getParams.data,
      currentTokenApproval: 0,
      currentTokenBalance: 0,
      gasPayer:getParams.gasPayer,
      gasPrice:getParams.gasPrice,
      gasToken:getParams.gasToken,
      functionName:getParams.functionName,
      url: "",
      contract: false
    }
    for(let c=1;c<9;c++){
      this.state['functionArg'+c] = getParams['functionArg'+c];
    }
  }
  componentDidMount(){
    this.poll()
    setInterval(this.poll.bind(this),1700)
  }
  deploySubscription() {
    let {web3,tx,contracts} = this.state
    console.log("Deploying Subscription Contract...")
    let code = require("./contracts/Subscription.bytecode.js")
    tx(contracts.Subscription._contract.deploy({data:code}),140000,(receipt)=>{
      console.log("~~~~~~ DEPLOY FROM DAPPARATUS:",receipt)
      if(receipt.contractAddress){
        axios.post(backendUrl+'deploysub', receipt, {
          headers: {
              'Content-Type': 'application/json',
          }
        }).then((response)=>{
          console.log("CACHE RESULT",response)
          window.location = "/"+receipt.contractAddress
        })
        .catch((error)=>{
          console.log(error);
        })
      }
    })

  }

  handleInput(e){
    let update = {}
    update[e.target.name] = e.target.value
    this.setState(update)
  }
  async poll() {
    if(this.state&& this.state.subscriptionContract){
      let subscriptionContractOwner = await this.state.subscriptionContract.owner().call()
      this.setState({subscriptionContractOwner:subscriptionContractOwner})
    }
    if(this.state&&this.state.tokenAddress&&this.state.tokenAddress.length==42&&this.state.subscriptionContract&&this.state.customContractLoader){

      let customTokenContract
      if(!this.state.customTokenContract){
        customTokenContract = this.state.customContractLoader("SomeStableToken",this.state.tokenAddress)
      }else if(this.state.customTokenContract._address!=this.state.tokenAddress){
        customTokenContract = this.state.customContractLoader("SomeStableToken",this.state.tokenAddress)
      }else{
        customTokenContract = this.state.customTokenContract
        //console.log("this.state.customTokenContract exists and you will need to check if the address has changed")
      }

      //console.log("SOME TOKEN CONTRACT IS LOADED AND READY:",customTokenContract._address)
      try{
        let approved = parseInt(await customTokenContract.allowance(this.state.account,this.state.subscriptionContract._address).call())/10**18
        let balance = parseInt(await customTokenContract.balanceOf(this.state.account).call())/10**18
        this.setState({customTokenContract:customTokenContract,currentTokenApproval:approved,currentTokenBalance:balance})
      }catch(e){
        console.log(e)
      }

    }
  }
  async sendSubscription(){
    let {account,toAddress,timeType,value,data,operation,subscriptionContract,web3,gasToken,gasPrice,gasPayer} = this.state

    if(!value) value=0

    let gasLimit = 360000 // TODO this will need to be a thing now with delegated exec

    if(!operation){
      operation=0
    }else{
      operation=parseInt(operation)
    }
    console.log("operation",operation)

    let periodSeconds = this.state.timeAmount;
    if(timeType=="minutes"){
      periodSeconds*=60
    }else if(timeType=="hours"){
      periodSeconds*=3600
    }else if(timeType=="days"){
      periodSeconds*=86400
    }else if(timeType=="months"){
      periodSeconds*=2592000
    }

    if(!gasToken||gasToken==0||gasToken=="0"||gasToken=="0x0"||gasToken=="0x00") gasToken = "0x0000000000000000000000000000000000000000"
    if(!gasPayer) gasPayer = "0x0000000000000000000000000000000000000000"
    if(!gasPrice) gasPrice = 0

    let txData = "0x00"
    if(data){
      txData=data;
    }

    /*
    address from, //the subscriber
    address to, //the publisher
    uint256 value, //amount in wei of ether sent from this contract to the to address
    bytes data, //the encoded transaction data (first four bytes of fn plus args, etc)
    Operation operation, //ENUM of operation
    uint256 periodSeconds, //the period in seconds between payments
    address gasToken, //the address of the token to pay relayer (0 for eth)
    uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
    address gasPayer, //the address that will pay the tokens to the relayer
    bytes signature //proof the subscriber signed the meta trasaction
     */

     console.log(
       this.state.account,
       this.state.toAddress,
       value*10**18,
       txData,
       operation,
       periodSeconds,
       gasToken,
       gasPrice*10**18,
       gasPayer,
     )

    const parts = [
      this.state.account,
      this.state.toAddress,
      web3.utils.toTwosComplement(value*10**18),
      txData,
      web3.utils.toTwosComplement(operation),
      web3.utils.toTwosComplement(periodSeconds),
      gasToken,
      web3.utils.toTwosComplement(gasPrice*10**18),
      gasPayer,
    ]
    /*web3.utils.padLeft("0x"+nonce,64),*/
    console.log("PARTS",parts)

    const subscriptionHash = await subscriptionContract.getSubscriptionHash(...parts).call()
    console.log("subscriptionHash",subscriptionHash)

    let signature = await web3.eth.personal.sign(""+subscriptionHash,account)
    console.log("signature",signature)
    let postData = {
      subscriptionContract:subscriptionContract._address,
      parts:parts,
      subscriptionHash: subscriptionHash,
      signature:signature,
    }

    axios.post(backendUrl+'saveSubscription', postData, {
      headers: {
          'Content-Type': 'application/json',
      }
    }).then((response)=>{
      console.log("TX RESULT",response)
    })
    .catch((error)=>{
      console.log(error);
    });
  }
  render() {
    let {web3,account,contracts,tx,gwei,block,avgBlockTime,etherscan,subscriptionContract} = this.state
    let connectedDisplay = []
    let contractsDisplay = []

    let mainTitle = ""

    if(web3){

      connectedDisplay.push(
       <Gas
         key="Gas"
         onUpdate={(state)=>{
           console.log("Gas price update:",state)
           this.setState(state,()=>{
             console.log("GWEI set:",this.state)
           })
         }}
       />
      )

      connectedDisplay.push(
        <ContractLoader
         key="ContractLoader"
         config={{DEBUG:true}}
         web3={web3}
         require={path => {return require(`${__dirname}/${path}`)}}
         onReady={(contracts,customLoader)=>{
               console.log("contracts loaded",contracts)

               let subscriptionContractAddress = window.location.pathname.replace("/","");
               let subscriptionContract
               if(subscriptionContractAddress){
                 subscriptionContract = customLoader("Subscription",subscriptionContractAddress)
               }else{
                 subscriptionContract = contracts.Subscription
               }

               this.setState({contracts:contracts,customContractLoader:customLoader,subscriptionContract:subscriptionContract})
         }}
        />
      )
      connectedDisplay.push(
        <Transactions
          key="Transactions"
          config={{DEBUG:false}}
          account={account}
          gwei={gwei}
          web3={web3}
          block={block}
          avgBlockTime={avgBlockTime}
          etherscan={etherscan}
          onReady={(state)=>{
            console.log("Transactions component is ready:",state)
            this.setState(state)
          }}
          onReceipt={(transaction,receipt)=>{
            // this is one way to get the deployed contract address, but instead I'll switch
            //  to a more straight forward callback system above
            console.log("Transaction Receipt",transaction,receipt)
          }}
        />
      )

      if(contracts&&subscriptionContract){

        let subscriptionContractAddress = window.location.pathname.replace("/","");
        if(!subscriptionContractAddress){
          mainTitle = (
            <div style={{padding:20,paddingTop:100}}>
              <div className="titleCenter" style={{marginTop:-50}}>
                <Scaler config={{origin:"center center"}}>
                <div style={{width:"100%",textAlign:"center",fontSize:120}}>
                 byoc.metatx.io
                </div>
                <div style={{width:"100%",textAlign:"center",fontSize:24}}>
                 <div>recurring subscriptions on the ethereum blockchain</div>
                 <div>set it and forget it delegate execution</div>
                </div>
                <div style={{width:"100%",textAlign:"center",fontSize:14,marginBottom:20}}>
                 please unlock metamask or mobile web3 provider
                </div>
                <div style={{width:"100%",textAlign:"center"}}>
                  <Button size="2" onClick={()=>{
                    window.location = "https://github.com/austintgriffith/token-subscription"
                  }}>
                  LEARN MORE
                  </Button>
                  <Button color="green" size="2" onClick={()=>{
                    this.deploySubscription()
                  }}>
                  DEPLOY SUBSCRIPTION CONTRACT
                  </Button>
                </div>
                </Scaler>
              </div>
            </div>
          )
        }
        else{
          mainTitle = (
            <div></div>
          )

          let subscribeButton = (
            <div style={{opacity:0.5}}>
              <Button color={"orange"} size="2" onClick={()=>{
                  alert("Please complete subscription information and approve tokens.")
                }}>
                Subscribe
              </Button>
            </div>
          )

          if(this.state.timeType && this.state.timeAmount && this.state.toAddress && this.state.toAddress.length==42 ){
            subscribeButton = (
              <div>
                <Button color={"green"} size="2" onClick={()=>{
                    this.sendSubscription()
                  }}>
                  Subscribe
                </Button>
              </div>
            )
          }

          let subscriptionOwnerDisplay = "connecting..."

          if(this.state && this.state.subscriptionContractOwner){
            if(this.state.subscriptionContractOwner=="0x0000000000000000000000000000000000000000"){
              subscriptionOwnerDisplay = (
                <div style={{fontSize:14,padding:5}}>
                  (This is the public Subscriptions contract. It can only send preappoved tokens to publishers. <a href="https://github.com/austintgriffith/token-subscription">read more</a>)
                </div>
              )
            }else{
              subscriptionOwnerDisplay = (
                <div>
                  <Address
                    {...this.state}
                    address={this.state.subscriptionContractOwner.toLowerCase()}
                  />
                </div>
              )
            }
          }

          let toAddressExtra = ""
          let txbuilder = ""

          //console.log("this.state.toAddress",this.state.toAddress)
          if(this.state.toAddress && this.state.toAddress.length==42){
            toAddressExtra = (
              <Address
                {...this.state}
                address={this.state.toAddress.toLowerCase()}
              />
            )
            txbuilder = (
              <TxBuilder {...this.state} onUpdate={update => {
                console.log("TXBUILDER UPDATE",update)
                this.setState(update)
              }}/>
            )
          }

          let buttonDisplay = ""
          let subscriberView = ""

          let isSubscriptionContractOwner = (this.state.subscriptionContractOwner && this.state.account && this.state.subscriptionContractOwner.toLowerCase()==this.state.account.toLowerCase())
          if(isSubscriptionContractOwner){
            subscriberView = (
              <Subscriptions backendUrl={backendUrl} {...this.state}/>
            )
          }
          buttonDisplay = (
            <div>
              {subscribeButton}
            </div>
          )

          contractsDisplay.push(
            <div key="UI" style={{padding:30}}>
              <div style={{padding:20}}>
                <a href="/">EIP 1337 - Delegate Call Subscriptions POC - (BYOC)</a> -   <Button onClick={()=>{
                    window.location = "https://github.com/austintgriffith/token-subscription"
                  }}>
                  LEARN MORE
                  </Button>
                <div>
                  <Address
                    {...this.state}
                    address={subscriptionContract._address}
                  />
                  {subscriptionOwnerDisplay}
                </div>
              </div>

              {subscriberView}

              <div style={{padding:20}}>
                <div style={{fontSize:40,padding:20}}>
                  Create Delegated Execution Subscription
                </div>

                <div>
                  Every <input
                      style={{verticalAlign:"middle",width:100,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                      type="text" name="timeAmount" value={this.state.timeAmount} onChange={this.handleInput.bind(this)}
                  />
                  <select name="timeType" value={this.state.timeType} onChange={this.handleInput.bind(this)} >
                    <option value="months">Month(s)</option>
                    <option value="days">Day(s)</option>
                    <option value="hours">Hour(s)</option>
                    <option value="minutes">Minute(s)</option>
                  </select>
                  <span style={{paddingLeft:10}}> execute:   <select name="operation" value={this.state.operation} onChange={this.handleInput.bind(this)} >
                      <option value="0">call()</option>
                      <option value="1">delegatCall()</option>
                      <option value="2">create()</option>
                    </select></span>
                </div>

                <div>
                On Contract Address:<input
                    style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                    type="text" name="toAddress" value={this.state.toAddress} onChange={this.handleInput.bind(this)}
                />
                {toAddressExtra}
                </div>

                <div>
                With Value:<input
                    style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                    type="text" name="value" value={this.state.value} onChange={this.handleInput.bind(this)}
                />
                </div>

                <div style={{margin:0,border:"1px solid #55555",backgroundColor:"#393939",padding:10}}>
                {txbuilder}
                Encoded Data Bytes:<input
                    style={{verticalAlign:"middle",width:600,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                    type="text" name="data" value={this.state.data} onChange={this.handleInput.bind(this)}
                />
                </div>


                <div style={{paddingTop:10,paddingBottom:10}}>
                  <div>
                  Gas Token:<input
                      style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                      type="text" name="gasToken" value={this.state.gasToken} onChange={this.handleInput.bind(this)}
                  />
                  </div>
                  <div>
                  Gas Price:<input
                      style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                      type="text" name="gasPrice" value={this.state.gasPrice} onChange={this.handleInput.bind(this)}
                  />
                  </div>
                  <div>
                  Gas Payer:<input
                      style={{verticalAlign:"middle",width:400,margin:6,maxHeight:20,padding:5,border:'2px solid #ccc',borderRadius:5}}
                      type="text" name="gasPayer" value={this.state.gasPayer} onChange={this.handleInput.bind(this)}
                  />
                  </div>
                </div>

              </div>

              {buttonDisplay}

              <Events
                config={{hide:false,DEBUG:false}}
                contract={subscriptionContract}
                eventName={"ExecuteSubscription"}
                block={block}
                /*filter={{from:this.state.account}}*/
                onUpdate={(eventData,allEvents)=>{
                  console.log("EVENT DATA:",eventData)
                  this.setState({events:allEvents})
                }}
              />

              <Events
                config={{hide:false,DEBUG:false}}
                contract={subscriptionContract}
                eventName={"FailedExecuteSubscription"}
                block={block}
                /*filter={{to:this.state.account}}*/
                onUpdate={(eventData,allEvents)=>{
                  console.log("EVENT DATA:",eventData)
                  this.setState({events:allEvents})
                }}
              />

              <Miner backendUrl={backendUrl} {...this.state} />
            </div>
          )
        }

      }

    }



    if(!mainTitle){
      mainTitle = (
        <div style={{padding:20,paddingTop:100}}>
          <div className="titleCenter" style={{marginTop:-50}}>
            <Scaler config={{origin:"center center"}}>
            <div style={{width:"100%",textAlign:"center",fontSize:120}}>
             sub.metatx.io
            </div>
            <div style={{width:"100%",textAlign:"center",fontSize:24}}>
             <div>recurring subscriptions on the ethereum blockchain</div>
             <div>set it and forget it token transfers</div>
            </div>
            <div style={{width:"100%",textAlign:"center",fontSize:14,marginBottom:20}}>
             please unlock metamask or mobile web3 provider
            </div>
            <div style={{width:"100%",textAlign:"center"}}>
              <Button size="2" onClick={()=>{
                window.location = "https://github.com/austintgriffith/token-subscription"
              }}>
              LEARN MORE
              </Button>
              <Button color="orange" size="2" onClick={()=>{
                alert("Please unlock Metamask or install web3 or mobile ethereum wallet.")
              }}>
              DEPLOY SUBSCRIPTION CONTRACT
              </Button>
            </div>
            </Scaler>
          </div>
        </div>
      )
    }

    return (
      <div className="App">
        <Metamask
          config={{requiredNetwork:['Unknown','Rinkeby']}}
          onUpdate={(state)=>{
           console.log("metamask state update:",state)
           if(state.web3Provider) {
             state.web3 = new Web3(state.web3Provider)
             this.setState(state)
           }
          }}
        />
        {mainTitle}
        {connectedDisplay}
        {contractsDisplay}

      </div>
    );
  }
}

export default App;
