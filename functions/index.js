const {setGlobalOptions} = require("firebase-functions");
const {
  onCall,
  HttpsError,
} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {defineSecret} = require("firebase-functions/params");

const admin = require("firebase-admin");
const {google} = require("googleapis");

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
  region: "europe-west1",
});

const PACKAGE_NAME = "com.munja.app";
const MUNJA_PRO_PRODUCT_ID = "munja.pro.monthly";

const googlePlayServiceAccount = defineSecret(
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
);

const ACTIVE_SUBSCRIPTION_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
]);

/**
 * Verifies a Google Play MUNJA PRO subscription.
 *
 * Expected callable payload:
 * {
 *   purchaseToken: "...",
 *   productId: "munja.pro.monthly"
 * }
 *
 * Security:
 * - Firebase Auth decides the uid.
 * - Google Play decides whether the subscription is valid.
 * - The client never writes isPro=true itself.
 */
exports.verifyMunjaProGooglePurchase = onCall(
    {
      region: "europe-west1",
      timeoutSeconds: 60,
      memory: "256MiB",
      secrets: [googlePlayServiceAccount],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to verify MUNJA PRO.",
        );
      }

      const uid = request.auth.uid;

      const data = request.data || {};

      const rawToken = data.purchaseToken;
      const rawProductId = data.productId;

      const purchaseToken =
        typeof rawToken === "string" ?
          rawToken.trim() :
          "";

      const productId =
        typeof rawProductId === "string" ?
          rawProductId.trim() :
          "";

      if (!purchaseToken) {
        throw new HttpsError(
            "invalid-argument",
            "Missing Google Play purchase token.",
        );
      }

      if (productId !== MUNJA_PRO_PRODUCT_ID) {
        throw new HttpsError(
            "invalid-argument",
            "Invalid MUNJA PRO product.",
        );
      }

      try {
        let serviceAccount;

        try {
          serviceAccount = JSON.parse(
              googlePlayServiceAccount.value(),
          );
        } catch (error) {
          logger.error(
              "MUNJA PRO GOOGLE VERIFY: invalid service account secret",
              {
                uid,
                error:
                  error && error.message ?
                    error.message :
                    String(error),
              },
          );

          throw new HttpsError(
              "internal",
              "Google Play verification is not configured correctly.",
          );
        }

        const auth = new google.auth.GoogleAuth({
          credentials: serviceAccount,
          scopes: [
            "https://www.googleapis.com/auth/androidpublisher",
          ],
        });

        const androidPublisher = google.androidpublisher({
          version: "v3",
          auth,
        });

        const response =
          await androidPublisher.purchases.subscriptionsv2.get({
            packageName: PACKAGE_NAME,
            token: purchaseToken,
          });

        const subscription = response.data;

        const state =
          subscription.subscriptionState || "";

        const lineItems =
          Array.isArray(subscription.lineItems) ?
            subscription.lineItems :
            [];

        const munjaLineItem = lineItems.find(
            (item) =>
              item.productId === MUNJA_PRO_PRODUCT_ID,
        );

        if (!munjaLineItem) {
          logger.warn(
              "MUNJA PRO VERIFY: product mismatch",
              {
                uid,
                state,
                lineItems,
              },
          );

          throw new HttpsError(
              "permission-denied",
              "This purchase does not contain MUNJA PRO.",
          );
        }

        const expiryRaw =
          munjaLineItem.expiryTime || null;

        const expiryDate =
          expiryRaw ? new Date(expiryRaw) : null;

        const expiryValid =
          expiryDate != null &&
          !Number.isNaN(expiryDate.getTime()) &&
          expiryDate.getTime() > Date.now();

        const stateAllowsAccess =
          ACTIVE_SUBSCRIPTION_STATES.has(state);

        const active =
          stateAllowsAccess && expiryValid;

        logger.info(
            "MUNJA PRO GOOGLE VERIFY",
            {
              uid,
              productId: munjaLineItem.productId,
              state,
              expiryTime: expiryRaw,
              active,
              testPurchase:
                subscription.testPurchase != null,
            },
        );

        if (!active) {
          await admin
              .firestore()
              .collection("users")
              .doc(uid)
              .set(
                  {
                    isPro: false,
                    proStatus: "free",
                    proSource: "google",
                    proProductId:
                      MUNJA_PRO_PRODUCT_ID,
                    proExpiresAt:
                      expiryValid ?
                        admin.firestore.Timestamp.fromDate(
                            expiryDate,
                        ) :
                        null,
                    proUpdatedAt:
                      admin.firestore.FieldValue.serverTimestamp(),
                  },
                  {merge: true},
              );

          throw new HttpsError(
              "failed-precondition",
              "Google Play does not report an active MUNJA PRO subscription.",
          );
        }

        const expiryTimestamp =
          admin.firestore.Timestamp.fromDate(
              expiryDate,
          );

        await admin
            .firestore()
            .collection("users")
            .doc(uid)
            .set(
                {
                  isPro: true,
                  proStatus: "active",
                  proSource: "google",
                  proProductId:
                    MUNJA_PRO_PRODUCT_ID,
                  proExpiresAt:
                    expiryTimestamp,
                  proUpdatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );

        return {
          success: true,
          active: true,
          source: "google",
          productId:
            MUNJA_PRO_PRODUCT_ID,
          subscriptionState: state,
          expiresAt:
            expiryDate.toISOString(),
          testPurchase:
            subscription.testPurchase != null,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        logger.error(
            "MUNJA PRO GOOGLE VERIFY ERROR",
            {
              uid,
              error:
                error && error.message ?
                  error.message :
                  String(error),
            },
        );

        throw new HttpsError(
            "internal",
            "Google Play subscription verification failed.",
        );
      }
    },
);
