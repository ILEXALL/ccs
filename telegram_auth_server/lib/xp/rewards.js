const { db } = require('../firebase-admin');
const { evaluateProfileXp, evaluateFirstCarXp } = require('./profile-garage-xp');
const { evaluatePermanentSpotApprovalXp } = require('./spot-xp');

const labels = {
  'profile.avatar': ['Add a profile photo', 'Добавить фото профиля', 'Pievienot profila foto'],
  'profile.bio': ['Write a bio (20+ characters)', 'Написать о себе (от 20 символов)', 'Aprakstīt sevi (vismaz 20 rakstzīmes)'],
  'profile.city': ['Add your city', 'Указать город', 'Norādīt pilsētu'],
  'profile.social': ['Add Instagram or Telegram', 'Добавить Instagram или Telegram', 'Pievienot Instagram vai Telegram'],
  'profile.full': ['Complete all four profile tasks', 'Выполнить все четыре задания профиля', 'Izpildīt visus četrus profila uzdevumus'],
  'garage.first_car': ['Add your first car', 'Добавить первую машину', 'Pievienot pirmo auto'],
  'garage.first_car_photo': ['Add a photo of your first car', 'Добавить фото первой машины', 'Pievienot pirmā auto foto'],
  'garage.first_car_description': ['Describe your first car (20+ characters)', 'Описать первую машину (от 20 символов)', 'Aprakstīt pirmo auto (vismaz 20 rakstzīmes)'],
  'garage.first_car_gallery': ['Add three different car photos', 'Добавить три разных фото машины', 'Pievienot trīs dažādus auto foto'],
  'garage.first_car_full': ['Complete car name, description, photo, build/use type and tags', 'Заполнить название, описание, фото, тип сборки или использования и теги машины', 'Aizpildīt auto nosaukumu, aprakstu, foto, būves vai lietojuma veidu un birkas'],
  'spot.approved': ['Publish a permanent spot approved by moderation', 'Опубликовать постоянный спот после одобрения модерацией', 'Publicēt moderatora apstiprinātu pastāvīgu vietu'],
  'spot.description': ['Add a description (20+ characters) to an approved spot', 'Описание от 20 символов у одобренного спота', 'Apstiprinātas vietas apraksts ar vismaz 20 rakstzīmēm'],
  'spot.photo': ['Add a photo to an approved spot', 'Фото у одобренного спота', 'Foto apstiprinātai vietai'],
  'spot.media_bundle': ['Three photos or a reel on an approved spot', 'Три фото или рилс у одобренного спота', 'Trīs foto vai reels apstiprinātai vietai'],
};

function rewardCatalog() {
  // Derive amounts from the award evaluators so the guide cannot invent rewards.
  const user = {photoUrl: 'photo', bio: 'A'.repeat(20), city: 'Riga', telegram: 'name',
    garage: [{name: 'Car', description: 'A'.repeat(20), photoPaths: ['a', 'b', 'c'], buildType: 'street', tags: ['car']}]};
  const awards = [...evaluateProfileXp('catalog', user), ...evaluateFirstCarXp('catalog', user),
    ...evaluatePermanentSpotApprovalXp('catalog', {addedByUid: 'catalog', status: 'approved',
      description: 'A'.repeat(20), photoUrls: ['a','b','c']})];
  return awards.map(award => {
    const [en, ru, lv] = labels[award.action];
    return {id: award.action, title: {en, ru, lv}, xp: award.amount,
      repeatable: award.objectType === 'spot', category: award.objectType};
  });
}

async function rewardProgress(userId) {
  const transactions = await db.collection('xp_transactions').where('userId', '==', userId).get();
  const rows = transactions.docs.map(doc => doc.data()).filter(row => !row.adjustmentOf);
  return {items: rewardCatalog().map(item => {
    const matching = rows.filter(row => row.action === item.id);
    const confirmed = matching.filter(row => row.status === 'confirmed');
    return {...item, completed: confirmed.length,
      earnedXp: confirmed.reduce((sum, row) => sum + row.amount, 0),
      pending: matching.filter(row => row.status === 'pending').length};
  })};
}
module.exports = {rewardCatalog, rewardProgress};
