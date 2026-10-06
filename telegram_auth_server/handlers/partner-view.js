const {admin,db} = require('../lib/firebase-admin');
const {recordPartnerView} = require('../lib/partner-views');
module.exports = async (req,res) => {
  if(req.method !== 'POST') return res.status(405).json({error:'Method not allowed'});
  let token;
  try {
    const header=req.headers.authorization || '';
    if(!header.startsWith('Bearer ')) throw Error();
    token=await admin.auth().verifyIdToken(header.slice(7),true);
  } catch {return res.status(401).json({error:'Sign in required'});}
  try {return res.status(200).json({uniqueViews:await recordPartnerView(db,token.uid,req.body?.partnerId)});}
  catch(e){return res.status(e.status||500).json({error:e.status?e.message:'Could not record view'});}
};
