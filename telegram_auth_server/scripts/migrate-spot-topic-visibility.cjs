const { db } = require('../lib/firebase-admin');
const apply = process.argv.includes('--apply');
(async()=>{
  for (const collection of ['spots','forum_topics']) {
    let last, changed=0;
    while(true) {
      let query=db.collection(collection).orderBy('__name__').limit(200);
      if(last) query=query.startAfter(last);
      const page=await query.get(); if(page.empty) break;
      for(const doc of page.docs) {
        if(doc.data().visibility!==undefined) continue;
        changed++;
        if(apply) await db.runTransaction(async tx=>{
          const fresh=await tx.get(doc.ref);
          if(fresh.exists && fresh.data().visibility===undefined) {
            if((fresh.data().sharedGroupIds || []).length) throw new Error('Unclassified group record: '+doc.ref.path);
            tx.update(doc.ref,{visibility:'public'});
          }
        });
      }
      last=page.docs.at(-1);
    }
    console.log(`${apply?'Migrated':'Would migrate'} ${changed} ${collection} documents`);
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
