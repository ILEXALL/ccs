const {createHandler,createAuthenticate,createReserve}=require('../lib/road-speed-limit');
const {admin,db}=require('../lib/firebase-admin');
module.exports=createHandler({authenticate:createAuthenticate(admin,db),reserve:createReserve(db)});
