#include "Timer.h"
#include "string.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "messageType.h"

#define NODECOUNT 20
#define TIMESLOT 100
#define Define_Nigh_List 500
#define Ask_Nigh_List 501
#define Reset 502

#define SIM_TIME sim_time()/10000000000.0;

#define Sink 21
//---------------------------------------------------------
#define SATRT 10
#define HELLO (uint8_t)1
#define DEGREE (uint8_t)2
#define DECIDE 3
#define UNDEC 4

#define INFO 503
#define PROP 504
#define DROP 505


typedef nx_struct PLATFORM_MESSAGE {
 nx_uint8_t type;
 nx_uint8_t sender;
 nx_uint8_t data;
 nx_uint8_t receiver;
 nx_uint8_t count;
 nx_uint8_t temp[0];
} PLATFORM_MESSAGE_t;


typedef nx_struct MESSAGE {
  nx_uint8_t type;
  nx_uint8_t sender;	//consume sender and receiver bytes of above message
  nx_uint8_t data;
} MESSAGE_t;

typedef nx_struct StartMsg {
  nx_uint8_t type;
  nx_uint8_t data;
} StartMsg;


int vc = 0;

 module even @safe() {
  uses {
    interface Leds;
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Random;

	  interface Timer<TMilli> as SendNighborListTimer;
    interface SplitControl as AMControl;
    interface Packet;
	  interface DataList<uint8_t> as myNeighbors;
    interface DataList<uint8_t> as proposer;

//---------------------------------------------------------------------
	  interface Timer<TMilli> as Sender;
	  interface Timer<TMilli> as Phase2;

    interface Timer<TMilli> as Round;
    interface Timer<TMilli> as Information;
	interface Receive as FReceive;
		interface Receive as BReceive;
    interface Receive as HReceive;
			interface Receive as DReceive;


  }
}

implementation {
  message_t neighbor_list_packet;
  message_t message;


  char finished=0;
  message_t out_packet;
  uint8_t myDegree=0;
  uint8_t p_hop=0;
  uint16_t MAX_RANDOM_TIME;
  uint16_t RANDOM_TIME;
  void reset();
  int R = 0;
  int delta = 0;

  int sent_bytes = 0;
  int recv_bytes = 0;
  int sent_counts = 0;
  int recv_counts = 0;
  int terminate = 0;
  int covered = 0;
  int C = -1;
  int number;

  int counter = 0;

  int my_parent = 1000;
  int my_level = 1000;
  int degree=0;
  int my_cross=0;
  int round =  0;
  bool radioBusy=FALSE,
       packetReady=FALSE,
       decide_recvd=FALSE,
       finish_forward=FALSE,
       forward_send = FALSE,
       forward_recvd= FALSE;
  bool tdma_first_fired = TRUE;
  bool hello_finish = FALSE;
  bool first_forward_sended = FALSE;
  bool covered_phase=FALSE;
  int children[NODECOUNT] = {NULL};
  int backward_children[NODECOUNT] = {NULL};
  int others[NODECOUNT] = {NULL};
  int neighcrossedge[NODECOUNT] = {NULL};
  int neighs_layer[NODECOUNT] = {NULL};
  
  bool DEBUG = FALSE;

	
//---------------------------------------------------------------------------

//------------------------------------------------------------------------------
  event void AMControl.startDone(error_t err) {
    if (err != SUCCESS)  call AMControl.start();
	//call Leds.set(0);
	 finished=0;

  }
//##################################################################################################
message_t* receive(message_t* bufPtr,void* pkt, uint8_t len);

/*Send message */
void send(uint8_t typ,uint8_t Data,uint8_t sender){
    MESSAGE_t* out_msg = (MESSAGE_t*)call Packet.getPayload(&out_packet, sizeof(MESSAGE_t));
    out_msg->type=typ;
    out_msg->sender=sender;
	  out_msg->data=Data;

    if(radioBusy==TRUE){
  		return;
  	}
    if (call AMSend.send(AM_BROADCAST_ADDR, &out_packet, sizeof(MESSAGE_t)) == SUCCESS) {
  	     radioBusy = TRUE;
  	}
    /*number = (call Random.rand16()%30)+1;
    printf("Number is %d\n",number );*/
    sent_bytes += sizeof(MESSAGE_t);
    sent_counts++;

	//call Sender.startOneShot(number);
}

double log2(int n)
{
  return log(n)/log(2);
}
event void SendNighborListTimer.fired() {
	int i=0;
	PLATFORM_MESSAGE_t *neighbor_list_msg = (PLATFORM_MESSAGE_t*)call Packet.getPayload(&neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)+call myNeighbors.getSize());
    neighbor_list_msg->data=0;
    neighbor_list_msg->sender=TOS_NODE_ID;
	neighbor_list_msg->type=Ask_Nigh_List;
	neighbor_list_msg->receiver=Sink;
	neighbor_list_msg->count=call myNeighbors.getSize();
	for(i=0;i<call myNeighbors.getSize();i++)
		neighbor_list_msg->temp[i]=call myNeighbors.get(i);
	if (call AMSend.send(Sink, &neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)+call myNeighbors.getSize()) == SUCCESS) {
		//call Leds.set(call myNeighbors.getSize());
	}
  call Leds.set(5);
}
//----------------------------------------------------------------------------------------
 bool isMyNeighbor(uint8_t id){
	int i=0;
	for(i=0;i<call myNeighbors.getSize();i++)
		if(call myNeighbors.get(i)==id)
			return 1;
	return -1;
 }
 bool getNeighborIndex(uint8_t id){
	int i=0;
	for(i=0;i<call myNeighbors.getSize();i++)
		if(call myNeighbors.get(i)==id)
			return i;
	return -1;
 }

bool  imax() /*komşularım içerisinde en büyük derecelimiyim,eşitlikte büyük idli nod seçilir*/
	{
		int i;
		int neighs_id;
		int max=neighcrossedge[0];
		for (i = 0; i < NODECOUNT; i++)
		{
			if(neighcrossedge[i]>=max)
			{
				max = neighcrossedge[i];
				neighs_id = i;
			}
		}
		if(my_cross>max) return TRUE;
		if(my_cross<max) return FALSE;
		if(my_cross==max)
		{
			if(TOS_NODE_ID>neighs_id) return TRUE;
			else return FALSE;
		}
	}

 int selectCanditate()
 {

   int i;
   int cand = 0;
   if(call myNeighbors.getSize() == 0)
   {
     return -1;
   }
   srand(call Round.getNow()%100);
   number = rand()%call myNeighbors.getSize();
   //printf("Number is %d \n",number);
   return cand = call myNeighbors.get(number);

 }
//------------------------------------------------------------------------------
void addToMyNeighborList( nx_uint8_t count, nx_uint8_t list[]){
	int i=0;
	for(i=0;i<count;i++)
		if((isMyNeighbor(list[i]) == -1 ) && (list[i]!=TOS_NODE_ID))
			call myNeighbors.add(list[i]);
	//call Leds.set(call myNeighbors.getSize());
}

void removeFromNeighborList(nx_uint8_t e)
{

		int idx = getNeighborIndex(e);
    call myNeighbors.getAndRemove(idx);

}

bool isElementOfProposer(uint8_t id){
 int i=0;
 for(i=0;i<call proposer.getSize();i++)
   if(call proposer.get(i)==id)
     return TRUE;
 return FALSE;
}

bool  search_lowest_id()
{
  int i,min_id;

  for (i = NODECOUNT; i > 0; i--)
  {
    if(neighs_layer[i]==1)
    {
                    min_id = i;
                    //break;
    }
  }
  if(TOS_NODE_ID > min_id)
    return TRUE;
  else
    return FALSE;
}

bool compare() //backward children ve children arraylerini karşılaştırmak için fonksiyon
{
  int i;
  for(i=0; i<NODECOUNT; i++)
                  {
					  /*if(TOS_NODE_ID == 0)
						{
							printf("%d children %d back child %d \n",i,children[i],backward_children[i]);
						}*/
					  if(children[i] != backward_children[i]) return FALSE;
				  }

  return TRUE;
}

bool all_neighs_response() //tüm komşularımı tanımladım mı ?
{
  int i;
  for (i= 0; i < NODECOUNT; i++)
  {
	/*if(TOS_NODE_ID == 0)
	{
		printf("%d children %d others %d == %d\n",i,children[i],others[i],isMyNeighbor(i));
	}*/
    if(i==my_parent) continue;
    if( (children[i] | others[i] )  != (isMyNeighbor(i) == 1)) return FALSE;
  }
  return TRUE;
}

void setLeds(uint16_t val) {
 if (val & 0x01)
   call Leds.led0On();
 else
   call Leds.led0Off();
 if (val & 0x02)
   call Leds.led1On();
 else
   call Leds.led1Off();
 if (val & 0x04)
   call Leds.led2On();
 else
   call Leds.led2Off();
}


event void Boot.booted() {
call Leds.set(1);

 call AMControl.start();
}


event void Round.fired()
{
  counter++;

		call Round.startOneShot(NODECOUNT*TIMESLOT);

if(counter==1)
  {
                  //paketi hazırla

                  Hpacket* packet;
                  packet = (Hpacket*)call Packet.getPayload(&message, sizeof(Hpacket));
                  packet->source=TOS_NODE_ID;

                  packetReady=TRUE;
                  if(radioBusy==FALSE && packetReady==TRUE)
                  {
                                  if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Hpacket)) == SUCCESS)
                                  {
                                                  if (DEBUG == TRUE) printf ("%d send hello message \n",TOS_NODE_ID);
                                                  //dbg_clear("OUT","%4.3f | %-3d Sent HELLO %d \n",SIM_TIME,TOS_NODE_ID,sizeof(Hpacket));
                                                  radioBusy=TRUE;
                                                  packetReady=FALSE;
                                                  sent_counts++;
                                                  sent_bytes += sizeof(Hpacket);
                                  }
                  }

                  tdma_first_fired = FALSE;
                  hello_finish = TRUE;
  }

		if((finish_forward==FALSE))
		{
			if((TOS_NODE_ID==0) && (first_forward_sended == FALSE) && counter == 2)
			{
				Fpacket* packet;
				my_level = 0;
				my_parent = 0;

				forward_send = TRUE;
				packet = (Fpacket*)call Packet.getPayload(&message, sizeof(Fpacket));
				packet->source=TOS_NODE_ID;

				packet->level = my_level;
				packet->parent = my_parent;
				packetReady=TRUE;

				if(radioBusy==FALSE && packetReady==TRUE)
				{
					if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Fpacket)) == SUCCESS)
					{

						radioBusy=TRUE;
						packetReady=FALSE;
						sent_counts++;
						sent_bytes += sizeof(Fpacket);
						finish_forward = TRUE;
					}
				}
				first_forward_sended = TRUE;

			}
			else if( (my_level==counter-1) && forward_recvd ==TRUE)
			{
				Fpacket* packet;
				packet = (Fpacket*)call Packet.getPayload(&message, sizeof(Fpacket));
				packet->source=TOS_NODE_ID;
				packet->level= my_level;
				packet->parent = my_parent;
				packetReady=TRUE;

				if(radioBusy==FALSE && packetReady==TRUE)
				{
					if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Fpacket)) == SUCCESS)
					{

						radioBusy=TRUE;
						packetReady=FALSE;
						sent_counts++;
						sent_bytes += sizeof(Fpacket);
						finish_forward = TRUE;
					}
				}

			}
		}
		else if(all_neighs_response() && compare() && covered_phase==FALSE)
		{
			Bpacket* packet;

			packet = (Bpacket*)call Packet.getPayload(&message, sizeof(Bpacket)); //parentıma backward atıyorum
			packet->source=TOS_NODE_ID;
			packet->level = my_level;
			packet->dest=my_parent;
			packet->cross=my_cross;
			packetReady=TRUE;
			if(radioBusy==FALSE && packetReady==TRUE)
			{
				if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Bpacket)) == SUCCESS)
				{

					radioBusy=TRUE;
					packetReady=FALSE;
					sent_counts++;
					sent_bytes += sizeof(Bpacket);

				}
			}
			covered_phase = TRUE;
		}
		else if(covered==0 && covered_phase==TRUE)
		{
			Dpacket* packet;
			if(my_level%2 == 0)
			{
				covered = 1;
				my_cross = 0;
				setLeds(4);
			}
			else
			{
				if(my_cross> 0 && imax()==TRUE)
				{
					covered = 1;
					my_cross = 0;
					packet = (Dpacket*)call Packet.getPayload(&message, sizeof(Dpacket));
					packet->type = DECIDE;
					packet->source=TOS_NODE_ID;
					packet->level = my_level;
					packet->cross=my_cross;
					packetReady=TRUE;
					if(radioBusy==FALSE && packetReady==TRUE)
					{
						if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Dpacket)) == SUCCESS)
						{


							radioBusy=TRUE;
							packetReady=FALSE;
							sent_counts++;
							sent_bytes += sizeof(Dpacket);
						}
					}
					setLeds(4);
				}
				else
				{
					if(decide_recvd==TRUE && covered == 0)
					{
						packet = (Dpacket*)call Packet.getPayload(&message, sizeof(Dpacket));
						packet->type = UNDEC;
						packet->source=TOS_NODE_ID;
						packet->level = my_level;
						packet->cross=my_cross;
						packetReady=TRUE;
						if(radioBusy==FALSE && packetReady==TRUE)
						{
							if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Dpacket)) == SUCCESS)
							{

								radioBusy=TRUE;
								packetReady=FALSE;
								sent_counts++;
								sent_bytes += sizeof(Dpacket);
							}
						}
					}
				}

			}
			decide_recvd = FALSE;
			if(covered==1 || my_cross ==0)
			{
				call Information.startOneShot(NODECOUNT*TIMESLOT);
				call Round.stop();
				//terminate = 1;
				if(covered==0)
					{
						setLeds(0);
					}
			}
		}
}

event void Information.fired()
{
  PLATFORM_MESSAGE_t *neighbor_list_msg = (PLATFORM_MESSAGE_t*)call Packet.getPayload(&neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)+call myNeighbors.getSize());
    neighbor_list_msg->type=INFO;
    neighbor_list_msg->sender=TOS_NODE_ID;
    neighbor_list_msg->data=recv_bytes;
    neighbor_list_msg->receiver=sent_bytes;
	neighbor_list_msg->count=covered;

	if (call AMSend.send(Sink, &neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)) == SUCCESS) {
    radioBusy=TRUE;
	}

   if (DEBUG == TRUE)printf("Node %d send %d receive %d covered %d\n",TOS_NODE_ID,sent_bytes,recv_bytes,covered);
  terminate = 1;

}

event message_t* FReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
	{
		if(len == sizeof(Fpacket))//forward mesajı alırsam
		{
			Fpacket* payload = (Fpacket*) pkt;

			if(isMyNeighbor(payload->source)==1)
			{
				setLeds(2);

				forward_recvd = TRUE;
				recv_counts++;
				recv_bytes += sizeof(Fpacket);

				if(my_parent==1000) //parentımı set etmediysem
				{
					my_parent = payload->source; //mesajı gönderen nodu parentım yapıyorum
					my_level = (payload->level)+1; //levelimi arttırıyorum
				}
				else if(payload->parent == TOS_NODE_ID) //mesajı gönderen nod parentında beni gösteriyorsa
				{
					children[payload->source] = 1; //child listeme ekliyorum
				}
				else //hiç biri değilse others listeme ekliyorum
				{
					others[payload->source] = 1;
				}
				if(payload->level == my_level)
				{
					my_cross++; //eğer kendi layerımdan forward alırsam cross edge sayımı arttırıyorum
				}
			}
		}
		return bufPtr;
	}

	event message_t* BReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
	{
		if(len == sizeof(Bpacket)) //backward mesajı aldığımda
		{
			Bpacket* payload = (Bpacket*) pkt;
			if(isMyNeighbor(payload->source)==1)
			{
				setLeds(3);
				if(payload->dest==TOS_NODE_ID)
				{

					backward_children[payload->source] = 1; //mesaj bana gönderildiyse gönderen nodu backward_children listeme ekliyorum
					recv_counts++;
					recv_bytes += sizeof(Bpacket);
				}
				if(payload->level==my_level)
				{

					neighcrossedge[payload->source] = payload->cross;
					neighs_layer[payload->source] = 1;
					recv_counts++;
					recv_bytes += sizeof(Bpacket);
				}
			}
		}
		return bufPtr;
	}

	event message_t* DReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
	{
		Dpacket* payload = (Dpacket*) pkt;
		if(isMyNeighbor(payload->source)==1)
		{
			if (len == sizeof(Dpacket) && payload->type == DECIDE)
			{
				if(payload->level == my_level && my_cross > 0)
				{

					recv_counts++;
					recv_bytes += sizeof(Dpacket);
					decide_recvd = TRUE;
					my_cross--;
					neighcrossedge[payload->source] = 0;
				}
			}

			if(len == sizeof(Dpacket) && payload->type == UNDEC)
			{
				if (payload->level == my_level && my_cross > 0)
				{

					recv_counts++;
					recv_bytes += sizeof(Dpacket);
					neighcrossedge[payload->source] = payload->cross;
				}
			}
		}
		return bufPtr;

	}
	
	event message_t* HReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
  Hpacket* payload = (Hpacket*)pkt;
                if(len==sizeof(Hpacket))
                { //hello paketi alırsam
                                //Hpacket* payload = (Hpacket*)pkt;

                                //dbg_clear("OUT","%4.3f | %-3d Received Packet from %d size of %d\n",SIM_TIME,TOS_NODE_ID, payload->source, len);
                                if (DEBUG == TRUE) printf("%d receive HELLO message from %d\n",TOS_NODE_ID,payload->source);

                                call myNeighbors.add(payload->source); //gönderen nodu komşuluk listeme ekliyorum
                                degree++;
                                recv_counts++;
                                recv_bytes += sizeof(Hpacket);
                }

                return bufPtr;

}
  event message_t* Receive.receive(message_t* bufPtr,void* pkt, uint8_t len) {
  uint8_t type=*(uint8_t*)pkt;
  uint8_t sender=*(uint8_t*)(pkt+1);
  if(type==Define_Nigh_List || type==Ask_Nigh_List || type==Reset){
    PLATFORM_MESSAGE_t* msg=(PLATFORM_MESSAGE_t*)pkt;
    if(msg->count>0)
      msg = (PLATFORM_MESSAGE_t*)call Packet.getPayload(bufPtr, sizeof(PLATFORM_MESSAGE_t)+msg->count);
    if(msg->type==Define_Nigh_List){
      addToMyNeighborList(msg->count,msg->temp);
      call Leds.set(msg->count);
  }
    else if(msg->type==Ask_Nigh_List){
      call SendNighborListTimer.startOneShot(TOS_NODE_ID*100);

    }
    else if(msg->type==Reset){
      call myNeighbors.clear();
      //call Leds.set(0);
      reset();
    }
    return bufPtr;
  }

  else return receive(bufPtr,pkt,len);
  }
//##################################################################################################
void reset(){
 myDegree=0;
 p_hop=0;
 MAX_RANDOM_TIME=0;
 RANDOM_TIME=0;
 call myNeighbors.clear();

 call Phase2.stop();
 call Sender.stop();
 call Leds.set(0);

}

 //---------------------------------------------------------------------------

//------------------------------------------------------------------------------
 event void Phase2.fired() {
	if(p_hop==0){
		call Phase2.stop();
	}
	else{
		send(DEGREE,myDegree,TOS_NODE_ID);
		--p_hop;
		}
  }
 //------------------------------------------------------------------------------
 event void Sender.fired() {
	if(radioBusy==TRUE){
		return;
	}
    if (call AMSend.send(AM_BROADCAST_ADDR, &out_packet, sizeof(MESSAGE_t)) == SUCCESS) {
	     radioBusy = TRUE;
	}
  }
  message_t* receive(message_t* bufPtr,void* pkt, uint8_t len){
  StartMsg* msg;
	msg=(StartMsg*)pkt;
	if(msg->type==SATRT && len == sizeof(StartMsg)){
		delta = msg->data;
    call Round.startOneShot((TOS_NODE_ID)*TIMESLOT);
    if (DEBUG == TRUE) printf ("The start message has been received delta is %d \n",delta);
    call Leds.set(delta);
		return bufPtr;
	}
	/*else if(msg->type==HELLO){
    printf("%d Hello message recvd from %d\n",TOS_NODE_ID, msg->sender);
    call myNeighbors.add(msg->sender);
    recv_bytes+= sizeof(MESSAGE_t);
    recv_counts++;
	}
  else if(msg->type==PROP && msg->data == TOS_NODE_ID && (isMyNeighbor(msg->sender) == 1))
  {
    printf("%d PROP message recvd from %d\n",TOS_NODE_ID, msg->sender);
    call proposer.add(msg->sender);
    recv_bytes+= sizeof(MESSAGE_t);
    recv_counts++;
  }
	else if(msg->type==DROP && (isMyNeighbor(msg->sender)==1))
  {
    //printf("%d receive drop message from %d\n",TOS_NODE_ID,msg->sender);
    if(C==msg->sender && isElementOfProposer(msg->sender)==FALSE)
      {
        C = -1;
        removeFromNeighborList(msg->sender);
      }
    else
    {
      removeFromNeighborList(msg->sender);
    }
    recv_bytes+= sizeof(MESSAGE_t);
    recv_counts++;
  }*/

	return bufPtr;
 }
//-------------------------------------------------------------------------------------
  event void AMControl.stopDone(error_t err) { }
  event void AMSend.sendDone(message_t* bufPtr, error_t error){radioBusy = FALSE;}
}
