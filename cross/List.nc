generic module List (typedef TYP,int n) {
 provides interface DataList<TYP>;
}
implementation {
 TYP list[n];
 int count=0;
 command void DataList.add(TYP d){
  if(count<n){
  atomic{
    list[count]=d;
    count++;
	}
  }
 }

 command TYP DataList.get(int i){
  TYP t;
  if(i<count)
    t=list[i];
   return(t);
  }

  command TYP DataList.getAndRemove(int i){
  int j;
  TYP t;
  atomic{
  if(i<count){
    t=list[i];
	for(j=i;j<count-1;j++)
	  list[j]=list[j+1];
    }
	count--;
   }
   return(t);
  }

 command int DataList.getSize(){
    return(count);
  }

   command TYP * DataList.getList(){
    return(list);
  }

    command void DataList.clear(){
    count=0;
  }
  /*command bool DataList.removeElement(TYP id){
 	int i;
  int j;
 	for(i=0;i<count;i++)
 		if(list[i]==id)
    {
      atomic{
      if(i<count){
    	for(j=i;j<count-1;j++)
    	  list[j]=list[j+1];
        }
    	count--;
       }
      return TRUE;
    }

 	return FALSE;
  }*/
}
