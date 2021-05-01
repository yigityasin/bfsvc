 interface DataList<TYP>{
 command void add(TYP d);
 command TYP get(int i);
 command int getSize();
 command TYP * getList();
 command TYP getAndRemove(int i);
 command void clear();
 //command bool removeElement(int id);
 }
