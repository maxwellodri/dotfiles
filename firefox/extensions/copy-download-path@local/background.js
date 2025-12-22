'use strict';

// Create the main context menu and submenus
browser.runtime.onInstalled.addListener(() => {
  createContextMenu();
});

// Create context menu when extension starts up
createContextMenu();

// Listen for context menu clicks
browser.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId.startsWith('copy-path-')) {
    const downloadId = parseInt(info.menuItemId.replace('copy-path-', ''));
    await copyDownloadPath(downloadId);
  }
});

// Create or update the context menu structure
async function createContextMenu() {
  // Remove all existing menu items first
  await browser.contextMenus.removeAll();
  
  // Get recent completed downloads
  const downloads = await browser.downloads.search({
    limit: 10,
    orderBy: ['-startTime'],
    state: 'complete'
  });
  
  if (downloads.length === 0) {
    // Create a disabled menu item if no downloads found
    browser.contextMenus.create({
      id: 'copy-download-path-main',
      title: 'CopyDownloadPath',
      contexts: ['page', 'selection', 'link', 'image', 'video', 'audio']
    });
    
    browser.contextMenus.create({
      parentId: 'copy-download-path-main',
      id: 'no-downloads',
      title: 'No completed downloads found',
      contexts: ['page', 'selection', 'link', 'image', 'video', 'audio']
    });
  } else {
    // Create main menu item
    browser.contextMenus.create({
      id: 'copy-download-path-main',
      title: 'CopyDownloadPath',
      contexts: ['page', 'selection', 'link', 'image', 'video', 'audio']
    });
    
    // Create submenu items for each download
    downloads.forEach((download, index) => {
      const title = download.filename.split('/').pop() || download.filename;
      const truncatedTitle = title.length > 50 ? title.substring(0, 47) + '...' : title;
      
      browser.contextMenus.create({
        parentId: 'copy-download-path-main',
        id: `copy-path-${download.id}`,
        title: truncatedTitle,
        contexts: ['page', 'selection', 'link', 'image', 'video', 'audio']
      });
    });
  }
}

// Copy download path to clipboard
async function copyDownloadPath(downloadId) {
  try {
    const downloads = await browser.downloads.search({ id: downloadId });
    
    if (downloads.length > 0) {
      const download = downloads[0];
      await navigator.clipboard.writeText(download.filename);
      
      // Show a temporary notification or badge (optional)
      console.log(`Copied to clipboard: ${download.filename}`);
    } else {
      console.error(`Download with ID ${downloadId} not found`);
    }
  } catch (error) {
    console.error('Failed to copy download path:', error);
  }
}

// Update context menu when downloads change
browser.downloads.onChanged.addListener(async (downloadDelta) => {
  if (downloadDelta.state) {
    // Refresh the menu when download state changes
    await createContextMenu();
  }
});

browser.downloads.onCreated.addListener(async () => {
  // Refresh the menu when new download is created
  await createContextMenu();
});

browser.downloads.onErased.addListener(async () => {
  // Refresh the menu when download is erased
  await createContextMenu();
});