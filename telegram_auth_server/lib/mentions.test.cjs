const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function fixture(file) {
  const records = new Map(Object.entries({
    'users/sender': {username:'Driver', usernameKey:'driver'},
    'users/john': {username:'John', usernameKey:'john'},
    'users/legacy': {username:'Legacy'},
    'users/outsider': {username:'Outside', usernameKey:'outside'},
    'chats/private': {memberIds:['sender','john'], isPrivate:true, isGroup:true},
    'chats/private/messages/msg': {senderUid:'sender',text:'Hi @JOHN @Outside @john @Driver'},
    'global_chat/msg': {userId:'sender', text:'Hi @John and @Legacy', countryCode:'LV'},
    'forum_topics/topic': {authorId:'sender',status:'approved',title:'Test'},
    'forum_topics/topic/replies/msg': {userId:'sender',text:'@Legacy hello'},
    'spots/spot': {status:'approved',name:'Spot',ownerUid:'sender'},
    'spot_reviews/review': {userId:'sender',type:'comment',spotId:'spot',comment:'@John hello'},
  }));
  const delivered=[], claims=new Set();
  const snapshot=p=>({id:p.split('/').at(-1),exists:records.has(p),data:()=>records.get(p)});
  const ref=p=>({get:async()=>snapshot(p),collection:n=>collection(p+'/'+n)});
  function collection(name) {
    const query=(key,op,values)=>({get:async()=>({docs:[...records.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===name.split('/').length+1&&(!key||values.includes(records.get(p)[key]))).map(snapshot)})});
    return {doc:id=>ref(name+'/'+id),where:query,select:()=>query()};
  }
  const source=fs.readFileSync(file,'utf8');
  const snippet=source.slice(source.indexOf('function mentionedUsernames'),source.indexOf('async function handleSpotComment'));
  const context={db:{collection},cleanText:(x,f='')=>typeof x==='string'&&x.trim()?x.trim():f,
    shortText:x=>String(x||''),cleanStringArray:x=>Array.isArray(x)?x:[],countryKey:x=>x,
    userHasActiveBan:x=>x.banned===true,
    sendPushToUser:async args=>{const key=args.deliveryKey+':'+args.userId;if(claims.has(key))return 0;claims.add(key);delivered.push(args);return 1;},exports:{}};
  vm.runInNewContext(snippet+'\nexports.handle=handleMentions;exports.parse=mentionedUsernames;',context);
  return {records, delivered, handle:context.exports.handle,parse:context.exports.parse};
}

for(const relative of ['../api/push-notification.js','../../api/push-notification.js']) {
  const file=path.resolve(__dirname,relative);
  test(`${relative}: parses complete handles, ignores emails and repeated tags`,()=>{
    const f=fixture(file);
    assert.deepEqual(Array.from(f.parse('mail a@john.com @@John @j @John, @JOHN (@Legacy)')),['john','legacy']);
  });
  test(`${relative}: private messages notify only members, once across retries`,async()=>{
    const f=fixture(file);
    const payload={chatId:'private',messageId:'msg',recipientUserIds:['outsider']};
    await f.handle('sender','chat_message',payload);
    await f.handle('sender','chat_message',payload);
    assert.equal(f.delivered.length,1);
    assert.equal(f.delivered[0].userId,'john');
    assert.equal(f.delivered[0].data.notificationKind,'mention');
    assert.equal(f.delivered[0].data.chatId,'private');
  });
  test(`${relative}: global, forum, and spot comments resolve canonical and legacy users`,async()=>{
    const f=fixture(file);
    await f.handle('sender','global_chat_message',{messageId:'msg'});
    await f.handle('sender','forum_reply',{topicId:'topic',messageId:'msg'});
    await f.handle('sender','spot_comment',{reviewId:'review'});
    assert.equal(f.delivered.length,4);
    assert.equal(f.delivered.filter(x=>x.userId==='legacy').length,2);
    assert.equal(f.delivered.at(-1).data.reviewId,'review');
    assert.equal(f.delivered.find(x=>x.data.type==='forum_reply').pushEnabled,false);
    assert.ok(f.delivered.every(x=>x.body.includes('mentioned you')));
  });
  test(`${relative}: forged authors, missing documents, pending topics, and inactive senders cannot notify`,async()=>{
    const f=fixture(file);
    await f.handle('outsider','global_chat_message',{messageId:'msg'});
    await f.handle('sender','spot_comment',{reviewId:'missing',text:'@John'});
    f.records.get('forum_topics/topic').status='pending';
    await f.handle('sender','forum_reply',{topicId:'topic',messageId:'msg'});
    f.records.get('users/sender').banned=true;
    await f.handle('sender','global_chat_message',{messageId:'msg'});
    assert.equal(f.delivered.length,0);
  });
  test(`${relative}: editing adds new recipients without notifying the same user again`,async()=>{
    const f=fixture(file);
    await f.handle('sender','spot_comment',{reviewId:'review'});
    f.records.get('spot_reviews/review').comment='@John and @Legacy';
    await f.handle('sender','spot_comment',{reviewId:'review'});
    assert.deepEqual(f.delivered.map(x=>x.userId),['john','legacy']);
  });
}
