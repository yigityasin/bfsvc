configuration evenApp {}
implementation {
  components MainC,even as App, LedsC,RandomC;
  components new AMSenderC(6);
  components new AMReceiverC(6);
  components new TimerMilliC() as T1;
  components new List(uint8_t,250) as List1;
  components new List(uint8_t,250) as List2;

  components new TimerMilliC() as T2;
    components new TimerMilliC() as T3;
    components new TimerMilliC() as Round;
    components new TimerMilliC() as Information;

  components ActiveMessageC;

  App.Random->RandomC;
  App.Boot -> MainC.Boot;
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Packet -> AMSenderC;
  App.SendNighborListTimer->T1;
  App.Round ->Round;
  App.myNeighbors->List1;
  App.proposer->List2;
  App.Sender->T3;
  App.Phase2->T2;
  App.Information->Information;

    App.HReceive -> AMReceiverC;
    App.FReceive -> AMReceiverC;
    App.BReceive -> AMReceiverC;
      App.DReceive -> AMReceiverC;

}
