#ifndef MESSAGETYPE_H
#define MESSAGETYPE_H
typedef nx_struct Hpacket
{
	nx_uint8_t source;
} Hpacket;
typedef nx_struct Fpacket
{
	nx_uint8_t source;
	nx_uint8_t parent;
	nx_uint8_t level;
}Fpacket;

typedef nx_struct Bpacket
{
	nx_uint8_t source;
	nx_uint8_t dest;
	nx_uint8_t cross;
	nx_uint8_t level;
}Bpacket;

typedef nx_struct Dpacket
{
	nx_uint8_t source;
	nx_uint8_t cross;
	nx_uint8_t level;
	nx_uint16_t type;
}Dpacket;

typedef nx_struct Info
{
	nx_uint16_t sendByte;
	nx_uint16_t recvByte;
	nx_uint16_t covered;
}Info;

/*typedef nx_struct StartMsg {
  nx_uint8_t type;
  nx_uint8_t sender;
  nx_uint8_t receiver;
} StartMsg;*/

#endif
