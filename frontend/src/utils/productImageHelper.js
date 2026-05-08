/**
 * Product Image Helper - Maps product types to local default images
 * Improved category detection with priority + better keyword handling
 */

import smartWatchImg from '../assets/images/default_smart_watch_image.jpeg';
import fanImg from '../assets/images/default_fan_image.jpeg';
import earphoneImg from '../assets/images/default_earphone_image.jpeg';
import acImg from '../assets/images/default_ac_image.jpeg';
import laptopTabletImg from '../assets/images/default_laptop_mobile_tablet_image.png';
import mobilePhoneImg from '../assets/images/default_laptop_mobile_tablet_image.png';
import refrigeratorImg from '../assets/images/default_refrigerator_image.jpeg';
import inverterImg from '../assets/images/default_inverter_image.jpeg'; // ✅ NEW
import productImg from '../assets/images/default_product_image.png';

// ✅ Image mapping
const IMAGE_MAPPING = {
  smartwatch: smartWatchImg,
  fan: fanImg,
  headphones: earphoneImg,
  ac: acImg,
  laptop: laptopTabletImg,
  tablet: laptopTabletImg,
  mobile: mobilePhoneImg,
  refrigerator: refrigeratorImg,
  inverter: inverterImg, // ✅ NEW
  generic: productImg,
};

// ✅ Improved keyword mapping (priority-based, no ambiguity)
const CATEGORY_KEYWORDS = {
  // 🔴 HIGH PRIORITY FIRST

  refrigerator: [
    'refrigerator',
    'fridge',
    'deep freezer',
    'freezer',
    'double door fridge',
    'single door fridge',
    'side by side refrigerator',
    'frost free refrigerator',
    'mini fridge'
  ],

  inverter: [
    'inverter',
    'inverter battery',
    'ups battery',
    'ups',
    'power backup',
    'battery inverter',
    'home inverter',
    'exide battery',
    'luminous inverter'
  ],

  ac: [
    'air conditioner',
    'air-conditioner',
    'ac unit'
    // ❌ removed "cooler"
  ],

  laptop: [
    'laptop',
    'notebook',
    'ultrabook',
    'macbook',
    'thinkpad',
    'chromebook',
    'gaming laptop'
  ],

  tablet: [
    'tablet',
    'ipad',
    'android tablet',
    'surface',
    'galaxy tab'
  ],

  mobile: [
    'mobile',
    'phone',
    'smartphone',
    'iphone',
    'android phone',
    'pixel',
    'oneplus',
    'xiaomi',
    'oppo',
    'vivo'
  ],

  smartwatch: [
    'smartwatch',
    'smart watch',
    'fitness tracker',
    'fitness band',
    'apple watch',
    'galaxy watch',
    'fitbit'
    // ❌ removed generic "watch"
  ],

  headphones: [
    'headphones',
    'earphones',
    'earbuds',
    'headset',
    'bluetooth headset',
    'wireless earbuds',
    'noise cancelling headphones'
  ],

  fan: [
    'ceiling fan',
    'table fan',
    'pedestal fan',
    'standing fan',
    'exhaust fan',
    'tower fan'
  ]
};

/**
 * 🔥 Smart category detection (priority + scoring)
 */

function detectCategory(productName = '', brand = '') {
  const text = `${productName} ${brand}`.toLowerCase();

  // 🔴 1. REFRIGERATOR (Highest priority)
  // refrigerator → fridge/freezer
  if (/\b(refrigerator|fridge|freezer|deep freezer)\b/.test(text)) {
    return 'refrigerator';
  }

  // 🔴 2. INVERTER (Second priority)
  // inverter → ups/battery
  if (/\b(inverter|ups|battery|power backup|home ups|back up)\b/.test(text)) {
    return 'inverter';
  }

  // 🔴 3. AC (Strict keywords only)
  // AC → air conditioner only
  // Avoid weak words like: cooling, system
  if (/\b(air conditioner|air-conditioner|split ac|window ac|ac unit)\b/.test(text) || /\bac\b/.test(text)) {
    return 'ac';
  }

  // 🔴 FALLBACK KEYWORD SCORING for other categories
  let bestMatch = { category: 'generic', score: 0 };

  for (const [category, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
    // Skip already handled high-priority categories
    if (['refrigerator', 'inverter', 'ac'].includes(category)) continue;

    keywords.forEach(keyword => {
      const regex = new RegExp(`\\b${keyword}\\b`);
      if (regex.test(text)) {
        const score = keyword.length;

        if (score > bestMatch.score) {
          bestMatch = { category, score };
        }
      }
    });
  }

  return bestMatch.category;
}

/**
 * Main function to get default product image
 * 🎯 PRIORITY LOGIC:
 * 1. Explicit Image URL (if real URL)
 * 2. Explicit Category (from AI/Backend)
 * 3. Strong Product Name Match
 * 4. Fallback
 */
export function getDefaultProductImage(productName, brand = '', currentUrl = '', category = '') {
  const normalizedCategory = category ? String(category).toLowerCase().trim() : '';

  // 1. USE EXPLICIT IMAGE (HIGHEST PRIORITY)
  // If currentUrl is a real external image, use it
  if (currentUrl && (currentUrl.startsWith('http') || currentUrl.startsWith('data:')) && !currentUrl.includes('default_')) {
    return currentUrl;
  }

  // 1b. Check if currentUrl matches our local placeholders
  if (currentUrl) {
    if (currentUrl.includes('smart_watch')) return IMAGE_MAPPING.smartwatch;
    if (currentUrl.includes('fan_image')) return IMAGE_MAPPING.fan;
    if (currentUrl.includes('earphone')) return IMAGE_MAPPING.headphones;
    if (currentUrl.includes('refrigerator')) return IMAGE_MAPPING.refrigerator;
    if (currentUrl.includes('ac_image')) return IMAGE_MAPPING.ac;
    if (currentUrl.includes('laptop_tablet')) return IMAGE_MAPPING.laptop;
    if (currentUrl.includes('mobile_phone')) return IMAGE_MAPPING.mobile;
    if (currentUrl.includes('inverter')) return IMAGE_MAPPING.inverter;
    if (currentUrl.includes('product_image')) return IMAGE_MAPPING.generic;
  }

  // 2. USE AI CATEGORY (IF AVAILABLE)
  let detectedCategory = 'generic';

  if (normalizedCategory) {
    // Direct mapping match
    if (IMAGE_MAPPING[normalizedCategory]) {
      detectedCategory = normalizedCategory;
    } else {
      // Detect from category description (e.g. "Home UPS / Inverter")
      const catResult = detectCategory(normalizedCategory, '');
      if (catResult !== 'generic') {
        detectedCategory = catResult;
      }
    }
  }

  // 3. USE STRONG PRODUCT NAME MATCH
  if (detectedCategory === 'generic' && productName) {
    detectedCategory = detectCategory(productName, brand);
  }

  // 5️⃣ DEBUG LOG (TEMP)
  console.log('--- Product Image Selection ---', {
    productName,
    brand,
    passedCategory: category,
    detectedCategory,
    hasCustomUrl: !!currentUrl
  });

  return IMAGE_MAPPING[detectedCategory] || IMAGE_MAPPING.generic;
}

/**
 * Get category name
 */
export function getProductCategory(productName, brand = '', category = '') {
  if (category) {
    const fromCat = detectCategory(category, '');
    if (fromCat !== 'generic') return fromCat;
  }

  if (!productName || typeof productName !== 'string') {
    return 'generic';
  }

  return detectCategory(productName, brand);
}

/**
 * Get all images
 */
export function getAllDefaultImages() {
  return { ...IMAGE_MAPPING };
}

export default {
  getDefaultProductImage,
  getProductCategory,
  getAllDefaultImages
};
