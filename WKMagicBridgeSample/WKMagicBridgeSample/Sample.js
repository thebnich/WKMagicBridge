wkutils.addHandler("PageTitle", function (message, sendResponse) {
  wkutils.print("Got PageTitle message!");
  sendResponse(document.title);
});
