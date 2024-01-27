
# https://developers.google.com/drive/api/quickstart/python
# pip install google-auth-oauthlib
# pip install --upgrade google-api-python-client google-auth-httplib2 google-auth-oauthlib

import os.path
import io

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaIoBaseDownload

# If modifying these scopes, delete the file token.json.
SCOPES = ["https://www.googleapis.com/auth/drive"]

def main():
  """Shows basic usage of the Drive v3 API.
  Prints the names and ids of the first 10 files the user has access to.
  """

  creds = Credentials.from_authorized_user_file("/var/tmp/token.json", SCOPES)
  if not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
      creds.refresh(Request())

  try:
    service = build("drive", "v3", credentials=creds)

    # query_details = "name contains 'pdf' and name contains 'TP IAC'"
    # query_details = "name contains 'pdf' and (name contains 'TP IAC' or name contains 'TP KUBE')"
    file_list = ${file_list}  # Here it is not Python, it is terraform template language - we get the list as a string (look for file_list in code)
  
    query_details = "name contains 'pdf' and ("
    for element in file_list:
        # Ajout de chaque élément à la chaîne de requête
        query_details += f"name contains '{element}' or "
    # Suppression du dernier "or" inutile
    query_details = query_details.rstrip("or ")
    # Fermeture de la parenthèse
    query_details += ")"

    # Call the Drive v3 API
    results = (
        service.files()
        .list(q=query_details, pageSize=10, fields="nextPageToken, files(id, name)")
        .execute()
    )
    items = results.get("files", [])
    service.close()

    if not items:
      print("No files found.")
      return
    print("Files:")
    for item in items:
      print(f"{item['name']} ({item['id']})")
      file_id = item['id']
      request = service.files().get_media(fileId=file_id)
      file = io.BytesIO()
      downloader = MediaIoBaseDownload(file, request)
      done = False
      while done is False:
        status, done = downloader.next_chunk()
        # print(f"Download {int(status.progress() * 100)}.")
        file_to_write = f"/var/www/html/{item['name']}"
        with open(file_to_write, "wb") as pdf:
          pdf.write(file.getvalue())


  except HttpError as error:
    # TODO(developer) - Handle errors from drive API.
    print(f"An error occurred: {error}")




if __name__ == "__main__":
  main()






