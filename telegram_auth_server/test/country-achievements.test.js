const test=require('node:test');const assert=require('node:assert/strict');
const {fixture}=require('./support');
const {countryForCoordinates,validateCountryFix}=require('../lib/xp/country-location');
const now=new Date('2026-09-18T12:00:00Z');
const fix={latitude:56.9496,longitude:24.1052,accuracy:15,recordedAtMillis:now.getTime()};
test('supported countries resolve from coordinates; unsupported countries and ocean do not',()=>{
 const places={AT:[48.208,16.373],BE:[50.85,4.352],BG:[42.698,23.322],HR:[45.815,15.982],CY:[34.678,33.041],CZ:[50.075,14.438],DK:[55.676,12.568],EE:[59.437,24.753],FI:[60.17,24.938],FR:[48.856,2.352],DE:[52.52,13.405],GR:[37.984,23.728],HU:[47.498,19.04],IE:[53.35,-6.26],IT:[41.902,12.496],LV:[56.9496,24.1052],LT:[54.687,25.279],LU:[49.612,6.131],MT:[35.899,14.514],NL:[52.367,4.904],PL:[52.23,21.012],PT:[38.722,-9.139],RO:[44.427,26.103],SK:[48.149,17.108],SI:[46.057,14.505],ES:[40.417,-3.704],SE:[59.329,18.069]};
 for(const [code,point] of Object.entries(places))assert.equal(countryForCoordinates(...point,code),code,code);
 assert.equal(countryForCoordinates(51.507,-0.128),null);assert.equal(countryForCoordinates(0,0),null);
});
test('freshness, accuracy, mock and coordinate checks',()=>{
 assert.equal(validateCountryFix(fix,now.getTime()),'LV');
 for(const change of [{latitude:91},{longitude:181},{accuracy:1001},{latitude:'56'},{recordedAtMillis:now.getTime()-400000},{isMocked:true}])assert.throws(()=>validateCountryFix({...fix,...change},now.getTime()),/fresh GPS/);
});
test('GPS grants only the current country once and public boards show only that country earned',async()=>{
 const f=fixture({'users/viewer':{}});f.rows.get('app_config/xp').achievements_enabled=true;
 const a=f.load('../lib/xp/achievements.js');
 const first=await a.recordCountryAchievement('tester',{...fix,countryCode:'DE',amount:9999},{now});
 assert.equal(first.countryCode,'LV');assert.equal(first.amount,75);assert.equal(first.awarded,true);
 assert.equal((await a.recordCountryAchievement('tester',fix,{now})).awarded,false);
 assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,75);
 const board=await a.publicAchievements('viewer','tester');
 assert.equal(board.items.find(i=>i.id==='tourist.LV').progress,1);
 assert.equal(board.items.find(i=>i.id==='tourist.DE').progress,0);
 assert.equal(board.items.find(i=>i.id==='tourist.DE').status,'locked');
 const award=[...f.rows.values()].find(v=>v.objectId==='tourist.LV');
 assert.equal(JSON.stringify(award).includes('latitude'),false);
 assert.equal(JSON.stringify(award).includes('longitude'),false);
 await a.recordCountryAchievement('tester',{...fix,latitude:54.687,longitude:25.279},{now});
 assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,150);
});
test('disabled or banned accounts and unsupported countries cannot receive rewards',async()=>{
 const f=fixture();const a=f.load('../lib/xp/achievements.js');
 assert.equal((await a.recordCountryAchievement('tester',fix,{now})).status,'disabled');
 f.rows.get('app_config/xp').achievements_enabled=true;
 assert.equal((await a.recordCountryAchievement('tester',{...fix,latitude:0,longitude:0},{now})).status,'unsupported');
 f.rows.get('users/tester').banned=true;
 assert.equal((await a.recordCountryAchievement('tester',fix,{now})).awarded,false);
 assert.equal(f.rows.has('xp_user_stats/tester'),false);
});
