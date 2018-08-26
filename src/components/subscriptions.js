import React, { Component } from 'react';
import { Address, Scaler } from "dapparatus"
import { soliditySha3 } from 'web3-utils';
import axios from 'axios';

let pollInterval
let pollTime = 2500

class Subscriptions extends Component {
  constructor(props) {
    super(props);
    this.state = {
      address:false,
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
      this.setState({subscriptions:response.data})
    })
    .catch((error)=>{
      console.log(error);
    });
  }
  render() {

    let subscriptions = []
    for(let s in this.state.subscriptions){
      if(this.state.subscriptions[s].subscriptionContract==this.props.subscriptionContract._address){
        subscriptions.push(
          <div style={{fontSize:12}}>
          <Address
            {...this.props}
            address={this.state.subscriptions[s].parts[0].toLowerCase()}
          /> {this.state.subscriptions[s].parts[1]} {this.state.subscriptions[s].parts[2]} 
          </div>
        )
      }
    }

    let title=""
    if(subscriptions.length>0){
      title=(
        <div style={{}}>
          Active Subscriptions
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
