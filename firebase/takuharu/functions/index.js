// たくはるファイナンス Cloud Functions
// 役割: 世帯の取引/コメントが新規作成されたら、相手メンバーへ FCM プッシュ通知。
// DB(asia-northeast1) と同リージョンに配置（v2 Firestore トリガの要件）。

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

const REGION = "asia-northeast1";

// 自分以外の世帯メンバーごとの {uid, tokens} と、表示名マップを取得。
async function targetsForOthers(hid, excludeUid) {
  const hsnap = await db.doc(`households/${hid}`).get();
  const members = hsnap.get("members") || [];
  const names = hsnap.get("memberNames") || {};
  const targets = [];
  for (const uid of members) {
    if (uid === excludeUid) continue;
    const usnap = await db.doc(`users/${uid}`).get();
    const t = usnap.get("fcmTokens");
    if (Array.isArray(t) && t.length) targets.push({uid, tokens: t});
  }
  return {targets, names};
}

// 各メンバーへ送信し、無効トークンを掃除する。
async function sendToTargets(targets, title, body, data) {
  for (const {uid, tokens} of targets) {
    let res;
    try {
      res = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {title, body},
        data: data || {},
        android: {priority: "high"},
      });
    } catch (e) {
      console.error("send failed", uid, e);
      continue;
    }
    const invalid = [];
    res.responses.forEach((r, i) => {
      if (!r.success) {
        const code = (r.error && r.error.code) || "";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-argument" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalid.push(tokens[i]);
        }
      }
    });
    if (invalid.length) {
      await db
          .doc(`users/${uid}`)
          .set({fcmTokens: FieldValue.arrayRemove(...invalid)}, {merge: true});
    }
  }
}

// 取引の新規作成 → 相手へ通知
exports.onTxCreated = onDocumentCreated(
    {document: "households/{hid}/transactions/{txId}", region: REGION},
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const t = snap.data() || {};
      const hid = event.params.hid;
      const author = t.recordedBy || "";
      const {targets, names} = await targetsForOthers(hid, author);
      if (!targets.length) return;

      const who = names[author] || "あいて";
      const isIncome = t.type === "income";
      const sign = isIncome ? "+" : "-";
      const amount = Number(t.amount || 0).toLocaleString("ja-JP");
      const cat = (t.category && t.category.major) || "";
      const desc = (t.description && String(t.description).trim()) || cat || "記録";
      const verb = isIncome ? "収入を記録したよ" : "記録したよ";
      const title = `${who} が${verb} ♡`;
      const body = `${desc}　${sign}¥${amount}`;
      await sendToTargets(targets, title, body, {
        type: "tx",
        hid,
        txId: event.params.txId,
      });
    },
);

// コメントの新規作成 → 相手へ通知
exports.onCommentCreated = onDocumentCreated(
    {
      document: "households/{hid}/transactions/{txId}/comments/{cid}",
      region: REGION,
    },
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const c = snap.data() || {};
      const hid = event.params.hid;
      const author = c.uid || "";
      const {targets, names} = await targetsForOthers(hid, author);
      if (!targets.length) return;

      const who = names[author] || "あいて";
      const title = `${who} からコメント ♡`;
      const body = String(c.text || "");
      await sendToTargets(targets, title, body, {
        type: "comment",
        hid,
        txId: event.params.txId,
      });
    },
);
