#!/usr/bin/env python3

import sys
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin

def extract_urls(page_url):
    try:
        response = requests.get(page_url, timeout=10)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.content, 'html.parser')
        links = soup.find_all('a', href=True)
        
        urls = {}
        for link in links:
            href = link.get('href')
            # Convert relative URLs to absolute URLs
            absolute_url = urljoin(page_url, href)
            urls[absolute_url] = True
        
        return list(urls.keys())
    
    except requests.RequestException as e:
        print(f"Error fetching {page_url}: {e}", file=sys.stderr)
        return []

def main():
    if len(sys.argv) != 2:
        print("Usage: python url_extractor.py <URL>", file=sys.stderr)
        sys.exit(1)
    
    page_url = sys.argv[1]
    urls = extract_urls(page_url)
    
    for url in urls:
        print(url)

if __name__ == "__main__":
    main()
