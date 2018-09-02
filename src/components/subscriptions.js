import React, { Component } from 'react';
import { Address, Button, Blockie  } from "dapparatus"
import axios from 'axios';

let pollInterval
let pollTime = 2500

const SubscriptionStatusEnum = [
  "ACTIVE",
  "PAUSED",
  "CANCELLED",
  "EXPIRED"
]

class Subscriptions extends Component {
  constructor(props) {
    super(props);
    this.state = {
      address:false,
      setStatus:{}
    }
  }
  componentDidMount(){
    pollInterval = setInterval(this.load.bind(this),pollTime)
    this.load()
  }
  componentWillUnmount(){
    clearInterval(pollInterval)
  }
  async load(){
    axios.get(this.props.backendUrl+"subscriptions")
    .then((response)=>{
      //console.log(response)
      this.setState({subscriptions:response.data},async ()=>{
        for(let s in this.state.subscriptions){

          let status = await this.props.subscriptionContract.getSubscriptionStatus(this.state.subscriptions[s].subscriptionHash).call()
          //console.log("SIGNED ",signed,this.state.subscriptions[s].subscriptionHash,)
          this.state.subscriptions[s].status=status
          //console.log(this.state.subscriptions)
          this.setState({subscriptions:this.state.subscriptions})
        }
      })
    })
    .catch((error)=>{
      console.log(error);
    });
  }
  handleInput(e){
    let update = {}
    update[e.target.name] = e.target.value
    this.setState(update)
  }
  render() {

    let subscriptions = []
    for(let s in this.state.subscriptions){
      if(this.state.subscriptions[s].subscriptionContract==this.props.subscriptionContract._address){



        let value = (this.props.web3.utils.toBN(this.state.subscriptions[s].parts[2])/(10**18)).toString()

        let period = this.props.web3.utils.hexToNumber(this.state.subscriptions[s].parts[5])

        let tokenValue = (this.props.web3.utils.toBN(this.state.subscriptions[s].parts[7])/(10**18)).toString()

        /*let button = (
          <Button color={this.state.subscriptions[s].signed?"green":"yellow"} onClick={()=>{
              this.props.tx(this.props.subscriptionContract.signSubscriptionHash(this.state.subscriptions[s].subscriptionHash),150000)
            }}>
            Save
          </Button>
        )*/



        let currentStatus = SubscriptionStatusEnum[this.state.subscriptions[s].status]

        let currentSetStatus = SubscriptionStatusEnum[this.state["setStatus"+s]]

        let setStatusButton = ""

        if(currentSetStatus && currentStatus!=currentSetStatus){
          setStatusButton = (
            <Button onClick={async ()=>{
              ///alert("SET STATUS TO "+this.state["setStatus"+s]+" FOR SUB HASH "+this.state.subscriptions[s].subscriptionHash)

              let parts = [
                this.state.subscriptions[s].subscriptionHash,
                this.props.web3.utils.toTwosComplement(this.state["setStatus"+s])
              ]

              const modifyStatusHash = await this.props.subscriptionContract.getModifyStatusHash(...parts).call()

              let signature = await this.props.web3.eth.personal.sign(""+modifyStatusHash,this.props.account)

              let postData = {
               subscriptionContract:this.props.subscriptionContract._address,
               parts:parts,
               modifyStatusHash: modifyStatusHash,
               signature:signature,
              }

              axios.post(this.props.backendUrl+'relayMetaTx', postData, {
               headers: {
                   'Content-Type': 'application/json',
               }
              }).then((response)=>{
               console.log("TX RESULT",response)
              })
              .catch((error)=>{
               console.log(error);
              });
            }}>
            save
            </Button>
          )
        }

        let statusOptions = SubscriptionStatusEnum.map((status,statusEnum)=>{
            let isSelected = false
            if(!this.state["setStatus"+s] && this.state.subscriptions[s].status==statusEnum){
              isSelected = true
            }
            return (
              <option selected={isSelected} key={"status"+statusEnum} value={statusEnum}>{status}</option>
            )
          }
        )

        let status = (
          <span>
            <select name={"setStatus"+s} value={this.state["setStatus"+s]} onChange={this.handleInput.bind(this)} >
              {statusOptions}
            </select>
            {setStatusButton}
          </span>
        )

        let gayPayer = this.state.subscriptions[s].parts[8]
        if(gayPayer == "0x0000000000000000000000000000000000000000"){
          gayPayer = this.props.subscriptionContract._address;
        }

        subscriptions.push(
          <div style={{fontSize:12}}>

            <Blockie address={this.state.subscriptions[s].parts[0]}/>

            =>

            <Blockie address={this.state.subscriptions[s].parts[1]}/>

            {value}

            /{period}s
            [
            <Blockie address={this.state.subscriptions[s].parts[6]}/>

            {tokenValue}
            <Blockie address={gayPayer}/>
            ]

            {status}

          </div>
        )
      }
    }

    let title=""
    if(subscriptions.length>0){
      title=(
        <div style={{color:"#dfdfdf"}}>
          Subscriptions:
        </div>
      )
    }

    return (
      <div style={{paddingLeft:40}}>
        {title}
        {subscriptions}
      </div>
    );
  }
}

export default Subscriptions;
