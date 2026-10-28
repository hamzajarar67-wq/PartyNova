const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

// Deploy this scheduled function to permanently remove chat messages older than 7 days.
exports.deleteExpiredChatMessages = onSchedule('every 24 hours', async () => {
  const cutoff = Timestamp.fromDate(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000));
  const conversations = await db.collection('conversations').get();
  for (const conversation of conversations.docs) {
    const messages = await conversation.ref.collection('messages')
      .where('createdAt', '<', cutoff).get();
    for (let i = 0; i < messages.docs.length; i += 400) {
      const batch = db.batch();
      for (const message of messages.docs.slice(i, i + 400)) batch.delete(message.ref);
      await batch.commit();
    }
    const remaining = await conversation.ref.collection('messages')
      .orderBy('createdAt', 'desc').limit(1).get();
    if (remaining.empty) {
      await conversation.ref.set({ lastMessage: '', lastMessageAt: null }, { merge: true });
    } else {
      const latest = remaining.docs[0].data();
      await conversation.ref.set({ lastMessage: latest.text || '', lastMessageAt: latest.createdAt || null }, { merge: true });
    }
  }
});
