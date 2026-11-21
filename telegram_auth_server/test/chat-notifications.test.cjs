const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
function fixture(){
 const sent=[];
 const chat={memberIds:['sender','recipient'],isGroup:false};
 const message={senderUid:'sender',senderUsername:'driver',text:'Hello'};
 const notification={userId:'recipient',type:'chat_message',title:'Messages',body:'Hello',read:false,createdAt:{toMillis:()=>1000},data:{type:'chat_message',chatId:'chat',messageId:'message'}};
 const db={collection(name){return {
  where(){return {get:async()=>({docs:[{id:'notification',data:()=>notification}]})};},
  get:async()=>({docs:[]}),
  doc(){return {get:async()=>({exists:true,data:()=>chat}),collection:()=>({doc:()=>({get:async()=>({exists:true,data:()=>message})})})};}
 };}};
 const context=vm.createContext({admin:{apps:[true],firestore:()=>db},console,capture:async args=>{sent.push(args);return 1;}});
 const source=fs.readFileSync(path.join(__dirname,'../api/push-notification.js'),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/export default /g,'').replace(/export /g,'');
 vm.runInContext(source+'\nsendPushToUser=capture;',context);
 return {context,sent};
}
test('chat push derives recipients from stored membership and carries navigation data',async()=>{
 const {context,sent}=fixture();
 await context.handleChatMessage('sender',{chatId:'chat',messageId:'message',recipientUserIds:['outsider']});
 assert.equal(sent.length,1);assert.equal(sent[0].userId,'recipient');
 assert.equal(sent[0].data.chatId,'chat');assert.equal(sent[0].settingName,'newMessageNotifications');
 assert.equal(sent[0].deliveryKey,'chat_message:chat:message');
 await context.handleChatMessage('outsider',{chatId:'chat',messageId:'message'});
 assert.equal(sent.length,1);
});
test('bell API preserves unread chat identity for navigation and badge filtering',async()=>{
 const {context}=fixture();const [item]=await context.notificationCenterItems('recipient');
 assert.equal(item.chatId,'chat');assert.equal(item.data.chatId,'chat');
 assert.equal(item.data.messageId,'message');assert.equal(item.read,false);
});
