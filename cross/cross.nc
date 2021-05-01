#include <Timer.h>
#include <stdio.h>
#include "messageType.h"

#define NODECOUNT 50
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

#define INFO (uint8_t)503
#define PROP (uint8_t)504
#define DROP (uint8_t)505


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
	nx_uint8_t sender;
	nx_uint8_t data;
} MESSAGE_t;


int vc = 0;

 module cross @safe() {
  uses 
  	{
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
		interface Receive as ChoosenReceive;
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

implementation 
{
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
	begin_backward = FALSE,
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
	bool choice_recvd= FALSE;
	bool choice_sended = FALSE;
	int covered_node = 0;
	int odd_cross =0;
	int even_cross = 0;
	int choice = 0;
	bool has_a_child = FALSE;

	bool DEBUG = FALSE;

//---------------------------------------------------------------------------

//------------------------------------------------------------------------------
  event void AMControl.startDone(error_t err) 
  {
    if (err != SUCCESS)  call AMControl.start();
	//call Leds.set(0);
	 finished=0;

  }
//##################################################################################################
message_t* receive(message_t* bufPtr,void* pkt, uint8_t len);

/*Send message */
void send(uint8_t typ,uint8_t Data,uint8_t sender)
{
    MESSAGE_t* out_msg = (MESSAGE_t*)call Packet.getPayload(&out_packet, sizeof(MESSAGE_t));
    out_msg->type=typ;
    //out_msg->sender=sender;
	out_msg->data=Data;

    if(radioBusy==TRUE)
    {
  		return;
  	}
    if (call AMSend.send(AM_BROADCAST_ADDR, &out_packet, sizeof(MESSAGE_t)) == SUCCESS) 
    {
  	     radioBusy = TRUE;
  	}
   
    sent_bytes += sizeof(MESSAGE_t);
    sent_counts++;
}

event void SendNighborListTimer.fired() 
{
	int i=0;
	PLATFORM_MESSAGE_t *neighbor_list_msg = (PLATFORM_MESSAGE_t*)call Packet.getPayload(&neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)+call myNeighbors.getSize());
    neighbor_list_msg->data=0;
    neighbor_list_msg->sender=TOS_NODE_ID;
	neighbor_list_msg->type=Ask_Nigh_List;
	neighbor_list_msg->receiver=Sink;
	neighbor_list_msg->count=call myNeighbors.getSize();
	for(i=0;i<call myNeighbors.getSize();i++)
		neighbor_list_msg->temp[i]=call myNeighbors.get(i);
	if (call AMSend.send(Sink, &neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)+call myNeighbors.getSize()) == SUCCESS) 
	{
		call Leds.set(call myNeighbors.getSize());
	}
}
bool isMyNeighbor(uint8_t id)
{
	int i=0;
	for(i=0;i<call myNeighbors.getSize();i++)
		if(call myNeighbors.get(i)==id)
			return 1;
	return -1;
 }
 bool getNeighborIndex(uint8_t id)
 {
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
void addToMyNeighborList( nx_uint8_t count, nx_uint8_t list[])
{
	int i=0;
	for(i=0;i<count;i++)
		if((isMyNeighbor(list[i]) == -1 ) && (list[i]!=TOS_NODE_ID))
			call myNeighbors.add(list[i]);
	
}

void removeFromNeighborList(nx_uint8_t e)
{
	int idx = getNeighborIndex(e);
    call myNeighbors.getAndRemove(idx);
}


bool compare() //backward children ve children arraylerini karşılaştırmak için fonksiyon
{
	int i;
	for(i=0; i<NODECOUNT; i++)
	{
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


event void Round.fired() //her nod komşularına hello mesajı atıyor bu sayede herkes komşularını bilmiş oluyor.
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
				if(DEBUG) printf("%d sent HELLO message \n",TOS_NODE_ID);
				//dbg_clear("OUT","%4.3f | %-3d Sent HELLO %d \n",SIM_TIME,TOS_NODE_ID,sizeof(Hpacket));
				radioBusy=TRUE;
				packetReady=FALSE;
				sent_counts++;
				sent_bytes += sizeof(Hpacket);
			}
		}

		hello_finish = TRUE;
	}
	else if((hello_finish == TRUE) && (begin_backward ==FALSE) && (finish_forward==FALSE) )
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
					if(DEBUG) printf("%d sent FORWARD message \n",TOS_NODE_ID);
					//dbg_clear("OUT","%4.3f | %-3d Sent FORWARD size of %d and \n",SIM_TIME,TOS_NODE_ID,sizeof(Fpacket));
					radioBusy=TRUE;
					packetReady=FALSE;
					sent_counts++;
					sent_bytes += sizeof(Fpacket);
					finish_forward = TRUE;
				}
			}
			first_forward_sended = TRUE;
		}
		else if( (my_level==counter-1))
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
					if(DEBUG) printf("%d sent FORWARD message \n",TOS_NODE_ID);
					//dbg_clear("OUT","%4.3f | %-3d Sent  FORWARD size of %d  \n",SIM_TIME,TOS_NODE_ID,sizeof(Fpacket));
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
		if(TOS_NODE_ID!=0)
		{
			Bpacket* packet;
			packet = (Bpacket*)call Packet.getPayload(&message, sizeof(Bpacket)); //parentıma backward atıyorum
			packet->source=TOS_NODE_ID;
			packet->level = my_level;
			packet->dest=my_parent;
			packet->cross=my_cross;

			if(my_level %2 == 0)
			{
				packet->even_level_cross_edge = even_cross+my_cross;
				packet->odd_level_cross_edge = odd_cross;
			}
			else
			{
				packet->even_level_cross_edge = even_cross;
				packet->odd_level_cross_edge = odd_cross+my_cross;
			}
			packetReady=TRUE;
			if(radioBusy==FALSE && packetReady==TRUE)
			{	
				if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Bpacket)) == SUCCESS)
				{
					if(DEBUG) printf("%d sent BACKWARD message \n",TOS_NODE_ID);
					//dbg_clear("OUT","%4.3f | %-3d Sent  Packet BACKWARD size of %d  \n",SIM_TIME,TOS_NODE_ID,sizeof(Bpacket));
					radioBusy=TRUE;
					packetReady=FALSE;
					sent_counts++;
					sent_bytes += sizeof(Bpacket);
				}
			}
		}
		else if(TOS_NODE_ID==0)
		{
			Choosenpacket* packet;
			packet = (Choosenpacket*)call Packet.getPayload(&message, sizeof(Choosenpacket)); 
			packet->source = TOS_NODE_ID;
			terminate = 1;
			call Round.stop();
			if(even_cross>=odd_cross)
			{
				packet->choose = 0;
				covered=1;
			}
			else
			{
				packet->choose = 1;
			}
			packetReady=TRUE;

			if(radioBusy==FALSE && packetReady==TRUE)
			{   
				if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Choosenpacket)) == SUCCESS)
				{
					if(DEBUG) printf("%d sent CHOICE message \n",TOS_NODE_ID);
					//dbg_clear("OUT","%4.3f | %-3d Sent Packet CHOICE size of %d \n",SIM_TIME,TOS_NODE_ID,sizeof(Hpacket));
					radioBusy=TRUE;
					packetReady=FALSE;
					sent_counts++;
					sent_bytes += sizeof(Choosenpacket);
					choice_sended = TRUE;

				}
			}
		}

		covered_phase = TRUE;
	}

	else if(choice_recvd ==TRUE && has_a_child == TRUE && choice_sended == FALSE)
	{
		Choosenpacket* packet;
		packet = (Choosenpacket*)call Packet.getPayload(&message, sizeof(Choosenpacket)); 
		packet->source = TOS_NODE_ID;
		packet->choose = choice;
		packetReady=TRUE;
		if(radioBusy==FALSE && packetReady==TRUE)
		{   
			if (call AMSend.send(AM_BROADCAST_ADDR,&message, sizeof(Choosenpacket)) == SUCCESS)
			{
				if(DEBUG) printf("%d sent CHOICE message %d\n",TOS_NODE_ID,choice);
				//dbg_clear("OUT","%4.3f | %-3d Sent Packet CHOICE %d size of %d \n",SIM_TIME,TOS_NODE_ID,choice,sizeof(Hpacket));
				radioBusy=TRUE;
				packetReady=FALSE;
				sent_counts++;
				sent_bytes += sizeof(Choosenpacket);
				choice_sended = TRUE;
			}
		}
	}
	else if(covered==0 && choice_recvd ==TRUE)
	{
		int i,j,k,l;
		Dpacket* packet;

		if(my_level%2 == choice && covered == 0)
		{
			covered = 1;
			covered_node++;
			my_cross = 0;
		}
		else 
		{
			if( my_cross> 0 && imax()==TRUE && covered == 0)
			{
				covered = 1;
				covered_node++;
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
						if(DEBUG) printf("%d sent DECIDE message \n",TOS_NODE_ID);
						//dbg_clear("OUT","%4.3f | %-3d Sent  Packet DECICE size of %d  \n",SIM_TIME,TOS_NODE_ID,sizeof(Dpacket));
						radioBusy=TRUE;
						packetReady=FALSE;
						sent_counts++;
						sent_bytes += sizeof(Dpacket);
					}
				}
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
							if(DEBUG) printf("%d sent UNDEC message \n",TOS_NODE_ID);
							//dbg_clear("OUT","%4.3f | %-3d Sent  Packet UNDEC size of %d  \n",SIM_TIME,TOS_NODE_ID,sizeof(Dpacket));
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

		if(covered==1 || my_cross ==0 )
		{
			//terminate = 1;
			call Round.stop();
			call Information.startOneShot(NODECOUNT*TIMESLOT);
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

	if (call AMSend.send(Sink, &neighbor_list_packet, sizeof(PLATFORM_MESSAGE_t)) == SUCCESS) 
	{
    	radioBusy=TRUE;
	}

 //if(DEBUG) {printf("Node %d send %d receive %d covered %d time %d\n",TOS_NODE_ID,sent_bytes,recv_bytes,covered,SIM_TIME);}
  printf("Node %d send %d receive %d covered %d time %lli \n",TOS_NODE_ID,sent_bytes,recv_bytes,covered, sim_time()/10000000000);
  terminate = 1;

}

event message_t* FReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	Fpacket* payload = (Fpacket*) pkt;

	if(len == sizeof(Fpacket) && isMyNeighbor(payload->source)==1)//forward mesajı alırsam
	{
		if(DEBUG) printf ("%d recv FORWARD message from %d\n",TOS_NODE_ID,payload->source);
		forward_recvd = TRUE;
		recv_counts++;
		recv_bytes += sizeof(Fpacket);
		forward_recvd = TRUE;

		if(my_parent==1000) //parentımı set etmediysem
		{
			my_parent = payload->source; //mesajı gönderen nodu parentım yapıyorum
			my_level = (payload->level)+1; //levelimi arttırıyorum
		}
		else if(payload->parent == TOS_NODE_ID) //mesajı gönderen nod parentında beni gösteriyorsa
		{
			children[payload->source] = 1; //child listeme ekliyorum
			has_a_child = TRUE;
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

	return bufPtr;

}

event message_t* BReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	Bpacket* payload = (Bpacket*) pkt;
	if(len == sizeof(Bpacket) && isMyNeighbor(payload->source)==1) //backward mesajı aldığımda
	{


		if(payload->dest==TOS_NODE_ID)
		{
			if(DEBUG) printf ("%d recv BACKWARD message from %d\n",TOS_NODE_ID,payload->source);
			backward_children[payload->source] = 1; //mesaj bana gönderildiyse gönderen nodu backward_children listeme ekliyorum
			recv_counts++;
			recv_bytes += sizeof(Bpacket);
			odd_cross += payload->odd_level_cross_edge;
			even_cross += payload->even_level_cross_edge;
		}
		if(payload->level==my_level)
		{
			if(DEBUG) printf ("%d recv BACKWARD message from %d\n",TOS_NODE_ID,payload->source);
			neighcrossedge[payload->source] = payload->cross;
			recv_counts++;
			recv_bytes += sizeof(Bpacket);
		}
	}

	return bufPtr;
}

event message_t* DReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	Dpacket* payload = (Dpacket*) pkt;
	if (len == sizeof(Dpacket) && payload->type == DECIDE && isMyNeighbor(payload->source)==1)
	{
		if(payload->level == my_level && my_cross > 0)
		{
			if(DEBUG) printf ("%d recv DECIDE message from %d\n",TOS_NODE_ID,payload->source);
			recv_counts++;
			recv_bytes += sizeof(Dpacket);
			decide_recvd = TRUE;
			my_cross--;
			neighcrossedge[payload->source] = 0;
		}
	}

	if(len == sizeof(Dpacket) && payload->type == UNDEC && isMyNeighbor(payload->source)==1)
	{
		if (payload->level == my_level && my_cross > 0)
		{
			if(DEBUG) printf ("%d recv UNDEC message from %d\n",TOS_NODE_ID,payload->source);
			recv_counts++;
			recv_bytes += sizeof(Dpacket);
			neighcrossedge[payload->source] = payload->cross;
		}
	}

	return bufPtr;
}


event message_t* ChoosenReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	Choosenpacket* payload = (Choosenpacket*) pkt;
	if(len == sizeof(Choosenpacket) && payload->source == my_parent)
	{
		if(DEBUG) 	printf ("%d recv CHOICE message from %d\n",TOS_NODE_ID,payload->source);
		choice_recvd =TRUE;
		recv_counts++;
		recv_bytes += sizeof(Choosenpacket);
		choice = payload->choose;
	}

	return bufPtr;
}
	
event message_t* HReceive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	Hpacket* payload = (Hpacket*)pkt;
	if(len==sizeof(Hpacket))
	{ 
		//hello paketi alırsam
		//Hpacket* payload = (Hpacket*)pkt;

		//dbg_clear("OUT","%4.3f | %d Received Packet from %d size of %d\n",SIM_TIME,TOS_NODE_ID, payload->source, len);
		if(DEBUG) printf("%d receive HELLO message from %d\n",TOS_NODE_ID,payload->source);

		call myNeighbors.add(payload->source); //gönderen nodu komşuluk listeme ekliyorum
		degree++;
		recv_counts++;
		recv_bytes += sizeof(Hpacket);
	}
	return bufPtr;
}
event message_t* Receive.receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	uint8_t type=*(uint8_t*)pkt;
	uint8_t sender=*(uint8_t*)(pkt+1);
	if(type==Define_Nigh_List || type==Ask_Nigh_List || type==Reset)
	{

		PLATFORM_MESSAGE_t* msg=(PLATFORM_MESSAGE_t*)pkt;
		if(DEBUG) printf("%d receive %d from %d\n",TOS_NODE_ID,type,sender);
		if(msg->count>0)
			msg = (PLATFORM_MESSAGE_t*)call Packet.getPayload(bufPtr, sizeof(PLATFORM_MESSAGE_t)+msg->count);
		if(msg->type==Define_Nigh_List)
		{
			addToMyNeighborList(msg->count,msg->temp);
			call Leds.set(msg->count);
		}
		else if(msg->type==Ask_Nigh_List)
		{
			call SendNighborListTimer.startOneShot(TOS_NODE_ID*100);
		}
		else if(msg->type==Reset)
		{
			call myNeighbors.clear();
		 	//call Leds.set(0);
			reset();
		}
		return bufPtr;
	}
	else return receive(bufPtr,pkt,len);
}

void reset()
{
 myDegree=0;
 p_hop=0;
 MAX_RANDOM_TIME=0;
 RANDOM_TIME=0;
 call myNeighbors.clear();

 call Phase2.stop();
 call Sender.stop();
 call Leds.set(0);
}

event void Phase2.fired() 
{
	if(p_hop==0)
	{
		call Phase2.stop();
	}
	else
	{
		send(DEGREE,myDegree,TOS_NODE_ID);
		--p_hop;
	}
}
 //------------------------------------------------------------------------------
event void Sender.fired() 
{
	if(radioBusy==TRUE)
	{
		return;
	}
	if (call AMSend.send(AM_BROADCAST_ADDR, &out_packet, sizeof(MESSAGE_t)) == SUCCESS) 
	{
		radioBusy = TRUE;
	}
}
message_t* receive(message_t* bufPtr,void* pkt, uint8_t len)
{
	StartMsg* msg;
	msg=(StartMsg*)pkt;
	if(msg->type==SATRT && len ==sizeof(StartMsg) )
	{
		delta = msg->data;
		call Round.startOneShot((TOS_NODE_ID)*TIMESLOT);
		if(DEBUG) printf ("The start message has been received delta is %d \n",delta);
		call Leds.set(delta);
		return bufPtr;
	}
}

  event void AMControl.stopDone(error_t err) { }
  event void AMSend.sendDone(message_t* bufPtr, error_t error){radioBusy = FALSE;}

}
