import Foundation

enum ExcludedDomains {
    static let defaultList: Set<String> = [
        "google.com", "youtube.com", "facebook.com", "twitter.com", "x.com",
        "instagram.com", "linkedin.com", "pinterest.com", "reddit.com",
        "wikipedia.org", "amazon.com", "apple.com", "microsoft.com",
        "github.com", "wordpress.org", "wordpress.com", "w3.org",
        "schema.org", "gravatar.com", "googleapis.com", "gstatic.com",
        "cloudflare.com", "cdn.jsdelivr.net", "unpkg.com",
        "vimeo.com", "dailymotion.com", "soundcloud.com",
        "paypal.com", "stripe.com", "shopify.com",
        "t.co", "bit.ly", "goo.gl", "tinyurl.com", "ow.ly", "buff.ly",
        "pxf.io", "sjv.io", "jdoqocy.com", "tkqlhce.com", "dpbolvw.net",
        "anrdoezrs.net", "kqzyfj.com", "avantlink.com", "shareasale.com",
        "awin1.com", "impact.com", "mailchi.mp", "mailchimp.com",
        "ebay.com", "etsy.com", "walmart.com", "target.com", "aliexpress.com",
        "bandcamp.com", "reverb.com",
        "godaddy.com", "namecheap.com", "bluehost.com", "hostgator.com",
        "squarespace.com", "wix.com", "weebly.com", "netlify.com",
        "herokuapp.com", "vercel.app", "pages.dev",
        "flickr.com", "imgur.com", "giphy.com", "tenor.com",
        "spotify.com", "tiktok.com", "twitch.tv", "discord.com", "discord.gg",
        "medium.com", "substack.com", "tumblr.com",
    ]

    static let excludedTLDs: Set<String> = [".edu", ".gov", ".mil", ".int"]

    static let suspectDomainLabels: Set<String> = [
        "co", "or", "ac", "go", "ne", "us", "eu", "uk", "de", "fr", "jp", "cn",
        "au", "nz", "za", "br", "in", "kr", "ru", "it", "es", "nl", "se", "no",
        "fi", "dk", "at", "ch", "be", "pt", "pl", "cz", "ie", "il", "mx", "ar", "cl",
    ]

    static func shouldExclude(domain: String, extra: Set<String> = []) -> Bool {
        let d = domain.lowercased()
        for tld in excludedTLDs {
            if d.hasSuffix(tld) { return true }
        }
        let all = defaultList.union(extra)
        for ex in all {
            if d == ex || d.hasSuffix("." + ex) { return true }
        }
        return false
    }
}
