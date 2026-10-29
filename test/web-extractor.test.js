import { test } from "node:test";
import assert from "node:assert";
import {
  sanitizeFileName,
  estimateReadingStats,
  resolveUrl,
  getDomainFromUrl,
  extractMetadata,
  extractPrimaryContent,
  buildPrintableHtml
} from "../src/web/web-extractor.js";

test("sanitizeFileName - strips illegal macOS filename characters", () => {
  assert.strictEqual(sanitizeFileName("How to Code: A Guide/Tutorial?"), "How to Code A Guide Tutorial.pdf");
  assert.strictEqual(sanitizeFileName('Article "Quoted" & <Special>'), "Article Quoted & Special.pdf");
  assert.strictEqual(sanitizeFileName("Title with | Pipe and * Asterisk"), "Title with Pipe and Asterisk.pdf");
});

test("sanitizeFileName - handles empty or whitespace input", () => {
  assert.strictEqual(sanitizeFileName(""), "webpage.pdf");
  assert.strictEqual(sanitizeFileName("   "), "webpage.pdf");
  assert.strictEqual(sanitizeFileName(null), "webpage.pdf");
  assert.strictEqual(sanitizeFileName(undefined), "webpage.pdf");
});

test("sanitizeFileName - truncates long titles cleanly", () => {
  const longTitle = "A".repeat(150);
  const result = sanitizeFileName(longTitle);
  assert.strictEqual(result.length, 104); // 100 chars + ".pdf"
  assert.ok(result.endsWith(".pdf"));
});

test("estimateReadingStats - computes word counts and estimated minutes", () => {
  const shortText = "This is a quick sentence.";
  assert.deepStrictEqual(estimateReadingStats(shortText), { wordCount: 5, readingTimeMinutes: 1 });

  const fourHundredWords = Array(400).fill("word").join(" ");
  assert.deepStrictEqual(estimateReadingStats(fourHundredWords), { wordCount: 400, readingTimeMinutes: 2 });

  assert.deepStrictEqual(estimateReadingStats(""), { wordCount: 0, readingTimeMinutes: 1 });
  assert.deepStrictEqual(estimateReadingStats(null), { wordCount: 0, readingTimeMinutes: 1 });
});

test("resolveUrl - resolves relative and absolute URLs properly", () => {
  const base = "https://example.com/blog/post-1";
  assert.strictEqual(resolveUrl("/assets/img.png", base), "https://example.com/assets/img.png");
  assert.strictEqual(resolveUrl("img2.png", base), "https://example.com/blog/img2.png");
  assert.strictEqual(resolveUrl("https://other.com/photo.jpg", base), "https://other.com/photo.jpg");
  assert.strictEqual(resolveUrl("data:image/png;base64,ABC", base), "data:image/png;base64,ABC");
  assert.strictEqual(resolveUrl("", base), "");
});

test("getDomainFromUrl - extracts clean domain name", () => {
  assert.strictEqual(getDomainFromUrl("https://www.nature.com/articles/123"), "nature.com");
  assert.strictEqual(getDomainFromUrl("http://blog.developer.apple.com/feed"), "blog.developer.apple.com");
  assert.strictEqual(getDomainFromUrl("invalid-url"), "");
  assert.strictEqual(getDomainFromUrl(""), "");
});

test("extractMetadata - extracts og, twitter and standard title/author/date", () => {
  const html = `
    <!DOCTYPE html>
    <html>
      <head>
        <meta property="og:title" content="Quantum Computing Breakthrough">
        <meta name="author" content="Dr. Alan Turing">
        <meta property="article:published_time" content="2026-10-15T09:00:00Z">
        <meta property="og:site_name" content="Tech Science Daily">
        <meta property="og:image" content="/images/quantum.jpg">
      </head>
      <body><h1>Fallback Header</h1></body>
    </html>
  `;
  const meta = extractMetadata(html, "https://techdaily.com/posts/quantum");
  assert.strictEqual(meta.title, "Quantum Computing Breakthrough");
  assert.strictEqual(meta.byline, "Dr. Alan Turing");
  assert.strictEqual(meta.publishedTime, "2026-10-15T09:00:00Z");
  assert.strictEqual(meta.siteName, "Tech Science Daily");
  assert.strictEqual(meta.leadImage, "https://techdaily.com/images/quantum.jpg");
});

test("extractPrimaryContent - extracts article and removes nav, sidebar, ads", () => {
  const samplePage = `
    <!DOCTYPE html>
    <html>
      <head>
        <title>Exploring Deep Space - Astronomy Magazine</title>
        <meta name="author" content="Carl Sagan">
      </head>
      <body>
        <nav class="navigation-bar">
          <a href="/home">Home</a> <a href="/news">News</a> <a href="/contact">Contact</a>
        </nav>
        <div class="ad advertisement-banner">
          <p>Buy our telescopes today at 50% discount!</p>
        </div>
        <div class="main-layout">
          <aside class="sidebar-widget">
            <h3>Trending Topics</h3>
            <ul><li>Mars 2026</li><li>Webb Telescope</li></ul>
          </aside>
          <article class="article-content">
            <h1>Exploring the Deepest Regions of Space</h1>
            <p>The universe is a vast expanse filled with billions of galaxies, each hosting countless solar systems and mysteries waiting to be solved by astronomers.</p>
            <p>Through modern space observatories, humanity has mapped distant exoplanets and cosmic background radiation from the dawn of creation itself.</p>
            <p>New missions plan to look even deeper into stellar nurseries to understand how prebiotic molecules formed in ancient proto-planetary disks.</p>
            <img src="telescope.jpg" alt="Space Telescope">
          </article>
        </div>
        <footer class="site-footer">
          <p>Copyright 2026 Astronomy Media. All rights reserved.</p>
        </footer>
      </body>
    </html>
  `;

  const result = extractPrimaryContent(samplePage, "https://astronomy.org/article");
  assert.strictEqual(result.title, "Exploring Deep Space - Astronomy Magazine");
  assert.strictEqual(result.byline, "Carl Sagan");
  assert.ok(result.wordCount > 50);
  assert.ok(result.contentHtml.includes("The universe is a vast expanse"));
  assert.ok(result.contentHtml.includes("https://astronomy.org/telescope.jpg"));
  // Ensure ads, nav, footer are not in the primary content
  assert.ok(!result.contentHtml.includes("Buy our telescopes"));
  assert.ok(!result.contentHtml.includes("Trending Topics"));
  assert.ok(!result.contentHtml.includes("Copyright 2026"));
});

test("extractPrimaryContent - strips Medium/TowardsDataScience headers, claps, follow buttons and duplicate title", () => {
  const mediumSample = `
    <!DOCTYPE html>
    <html>
      <head>
        <title>How Claude Helped Me Build My $200k ML Resume | Towards Data Science</title>
        <meta name="author" content="Jane Data">
        <meta property="og:site_name" content="Towards Data Science">
      </head>
      <body>
        <div class="site-header">
          <a href="/">Towards Data Science</a>
          <button>Open in app</button>
          <a href="/signin">Sign in</a>
        </div>
        <article>
          <header class="entry-header">
            <div class="author-card">
              <span>Jane Data</span>
              <button class="follow-btn">Follow</button>
              <span>8 min read</span>
            </div>
            <div class="action-bar">
              <span class="clap-count">1.2K claps</span>
              <span class="speechify-listen">Listen</span>
              <span class="share-btn">Share</span>
            </div>
            <h1>How Claude Helped Me Build My $200k ML Resume</h1>
            <p class="subtitle">A detailed breakdown of prompt engineering my resume.</p>
          </header>
          <section class="story-body">
            <p>Landing a senior machine learning engineering role in 2026 requires more than just listing tools and libraries.</p>
            <p>When I started updating my resume, I realized that traditional bullet points failed to capture the impact of distributed model training.</p>
            <p>Here is the exact step-by-step strategy I used with Claude to highlight business metrics, GPU efficiency gains, and architectural decisions.</p>
          </section>
        </article>
      </body>
    </html>
  `;
  const result = extractPrimaryContent(mediumSample, "https://towardsdatascience.com/how-claude-help-me-build-my-200k-ml-resume/");
  assert.strictEqual(result.title, "How Claude Helped Me Build My $200k ML Resume | Towards Data Science");
  assert.strictEqual(result.byline, "Jane Data");
  assert.strictEqual(result.siteName, "Towards Data Science");
  assert.ok(result.contentHtml.includes("Landing a senior machine learning engineering role"));
  assert.ok(result.contentHtml.includes("Here is the exact step-by-step strategy"));

  // Ensure top clutter is completely absent
  assert.ok(!result.contentHtml.includes("Towards Data Science"));
  assert.ok(!result.contentHtml.includes("Open in app"));
  assert.ok(!result.contentHtml.includes("Sign in"));
  assert.ok(!result.contentHtml.includes("1.2K claps"));
  assert.ok(!result.contentHtml.includes("Listen"));
  assert.ok(!result.contentHtml.includes("Share"));
  assert.ok(!result.contentHtml.includes("Follow"));
  // Ensure duplicate H1 is not repeated at the top of the body
  assert.ok(!result.contentHtml.includes("<h1>How Claude Helped Me Build My $200k ML Resume</h1>"));
});

test("extractPrimaryContent - strips breadcrumbs, kickers, and social share bars in generic layouts", () => {
  const genericNews = `
    <html>
      <head><title>Global Climate Summit Reaches Agreement</title></head>
      <body>
        <nav class="top-nav"><a href="/">Home</a> > <a href="/world">World</a> > <a href="/climate">Climate</a></nav>
        <div class="content-wrapper">
          <div class="kicker-banner">BREAKING NEWS - LIVE UPDATES</div>
          <div class="social-share-bar"><button>Tweet</button><button>Share</button></div>
          <div class="post-content">
            <h1>Global Climate Summit Reaches Agreement</h1>
            <p>Representatives from over 190 nations have reached a landmark consensus on emissions reduction targets.</p>
            <p>The accord establishes strict monitoring frameworks and funding mechanisms for vulnerable coastal economies.</p>
            <p>Delegates celebrated the breakthrough after four straight days of round-the-clock negotiations.</p>
          </div>
          <div class="trending-sidebar"><h3>Related Stories</h3><ul><li>Carbon Tax Updates</li></ul></div>
        </div>
      </body>
    </html>
  `;
  const result = extractPrimaryContent(genericNews, "https://news.org/climate");
  assert.strictEqual(result.title, "Global Climate Summit Reaches Agreement");
  assert.ok(result.contentHtml.includes("Representatives from over 190 nations"));
  assert.ok(!result.contentHtml.includes("BREAKING NEWS"));
  assert.ok(!result.contentHtml.includes("Related Stories"));
  assert.ok(!result.contentHtml.includes("Carbon Tax"));
  assert.ok(!result.contentHtml.includes("<h1>Global Climate Summit Reaches Agreement</h1>"));
});

test("extractPrimaryContent - supports full mode", () => {
  const samplePage = `
    <html>
      <head><title>Simple Page</title></head>
      <body>
        <div><p>Simple sentence for testing full page content capture.</p></div>
      </body>
    </html>
  `;
  const result = extractPrimaryContent(samplePage, "https://example.com", { mode: "full" });
  assert.strictEqual(result.title, "Simple Page");
  assert.ok(result.contentHtml.includes("Simple sentence for testing full page content capture."));
});

test("buildPrintableHtml - generates valid HTML with print typography and styles", () => {
  const article = {
    title: "Understanding Microservices",
    byline: "Martin Fowler",
    siteName: "martinfowler.com",
    publishedTime: "2026-05-10T12:00:00Z",
    leadImage: "https://martinfowler.com/lead.png",
    contentHtml: "<p>Microservice architecture structures an application as a collection of services.</p>",
    wordCount: 150,
    readingTimeMinutes: 1,
    url: "https://martinfowler.com/articles/microservices"
  };

  const html = buildPrintableHtml(article, { paperSize: "A4" });
  assert.ok(html.includes("<!DOCTYPE html>"));
  assert.ok(html.includes("@page {"));
  assert.ok(html.includes("size: A4;"));
  assert.ok(html.includes("Understanding Microservices"));
  assert.ok(html.includes("Martin Fowler"));
  assert.ok(html.includes("https://martinfowler.com/lead.png"));
  assert.ok(html.includes("Microservice architecture"));
});
