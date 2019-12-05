#!/bin/bash

# Set your Intercom Workspace Access Token
accessToken="<access token here>"

# Create some files for temporary storage
allConvosJsonFile="all_convos.json"
allConvoIDsFile="all_convo_IDs.txt"
fullConvosJsonFile="convo_history.json"

# Create a CSV file for storing the conversation history
fullConvosCsvFile="convo_history.csv"

# Ensure all files are empty before using
> $allConvosJsonFile
> $allConvoIDsFile
> $fullConvosCsvFile
> $fullConvosJsonFile

# Get a list of all the conversations in Intercom and store in a json file
curl -s "https://api.intercom.io/conversations?display_as=plaintext" \
-H 'Authorization:Bearer '$accessToken -H 'Accept:application/json' > $allConvosJsonFile

# Conversation lists are paginated so first determine how mnany pages there are
# and the number of conversations per page.
total_convo_pages=`cat $allConvosJsonFile | jq .pages.total_pages`
current_page_total=`cat $allConvosJsonFile | jq '.conversations | length'`
next_page_url=`cat $allConvosJsonFile | jq -r .pages.next`

# Iterate through each page of the conversations list
for (( x=0; x<$total_convo_pages; x++ ))
do
  # Iterate through each conversation on the current page and store the
  # conversation ids in a file
  for (( y=0; y<$current_page_total; y++ ))
  do
     cat $allConvosJsonFile | jq -r .conversations[$y].id >> $allConvoIDsFile
  done

  # Only request the next page of results if another page url exists.
  if [ "$next_page_url" != null ]; then
    curl -s "$next_page_url" -H 'Authorization:Bearer '$accessToken \
    -H 'Accept:application/json' > $allConvosJsonFile
    # Do a new count on the next page list of conversations and also capture
    # the subsequent page url if any
    current_page_total=`cat $allConvosJsonFile | jq '.conversations | length'`
    if [ "$current_page_total" == "" ]; then
      current_page_total=0
      echo "Page failed to return results!"
    fi
    next_page_url=`cat $allConvosJsonFile | jq -r .pages.next`
  fi
done

# Create the first line in the csv file with the column names
echo "Conversation_ID, User_Type, Intercom_User_ID, Assignee_ID, Assignee_Type, \
Message_ID, Message_Type, Message_Delivered_As, Message_Subject, Message_Body, \
Author_Type, Author_ID, Author_Name, Author_Email, Attachments_Type, Attachments_Name, \
Attachments_URL, Customer_First_Reply_Created_At, Customer_First_Reply_Type, \
Created_At, Updated_At, Waiting_Since, Snoozed_Until, Notified_At, Conversation_State, \
Conversation_Open, Conversation_Read, Conversation_Rating, Conversation_Remark, \
Conversation_Rating_Created_At, Tags"  > $fullConvosCsvFile

# Now that you have the full list of conversation ids in a file,
# use a while loop to iterate through each one
while IFS='' read -r convoId || [[ -n "$convoId" ]]; do
   # Using the current conversation id, pull down the
   # conversation object from the Intercom API
   curl -s "https://api.intercom.io/conversations/$convoId" \
   -H 'Authorization:Bearer '$accessToken -H 'Accept:application/json' > $fullConvosJsonFile
   # Once retrieved, store how many conversation parts exist in the conversation object
   total_message_parts=`cat $fullConvosJsonFile | jq '.conversation_parts.total_count | length'`
   # As the first conversation message is outside of the conversation parts array,
   # you'll need to store that in the csv file first
   cat $fullConvosJsonFile | jq -r "[\
   .id, .user.type, .user.id, .assignee.id, .assignee.type,\
   .conversation_message.id, .conversation_message.type,\
   .conversation_message.delivered_as, .conversation_message.subject,\
   .conversation_message.body, .conversation_message.author.type,\
   .conversation_message.author.id, .conversation_message.author.name,\
   .conversation_message.author.email, .conversation_message.attachments[0].type,\
   .conversation_message.attachments[0].name, .conversation_message.attachments[0].url,\
   .customer_first_reply.created_at, .customer_first_reply.type,\
   .created_at, .updated_at, .waiting_since, .snoozed_until,
   .conversation_parts.conversation_parts[0].notified_at, .state, .open, .read,\
   .conversation_rating.rating, .conversation_rating.remark,\
   .conversation_rating.created_at, .tags.tags[].name\
   ] | @csv" >> $fullConvosCsvFile

   # Now iterate through all the conversation parts (messages,notes,etc) and
   # append each one to the next line of the csv file)
   for (( z=0; z<$total_message_parts; z++ ))
   do
         cat $fullConvosJsonFile | jq -r "[\
         .id, .user.type, .user.id,\
         .conversation_parts.conversation_parts[$z].assigned_to.id,\
         .conversation_parts.conversation_parts[$z].assigned_to.type,\
         .conversation_parts.conversation_parts[$z].id,\
         .conversation_parts.conversation_parts[$z].type,\
         .conversation_parts.conversation_parts[$z].part_type,\
         .conversation_message.subject,\
         .conversation_parts.conversation_parts[$z].body,\
         .conversation_parts.conversation_parts[$z].author.type,\
         .conversation_parts.conversation_parts[$z].author.id,\
         .conversation_parts.conversation_parts[$z].author.name,\
         .conversation_parts.conversation_parts[$z].author.email,\
         .conversation_parts.conversation_parts[$z].attachments[0].type,\
         .conversation_parts.conversation_parts[$z].attachments[0].name,\
         .conversation_parts.conversation_parts[$z].attachments[0].url,\
         null, null, .conversation_parts.conversation_parts[$z].created_at,\
         .conversation_parts.conversation_parts[$z].updated_at,\
         null, null, .conversation_parts.conversation_parts[$z].notified_at,\
         .state, .open, .read, null, null, null\
         ] | @csv" >> $fullConvosCsvFile
   done
   # sleep 1    # It's good practice to trottle the requests to keep under the API rate limit
done < "$allConvoIDsFile"  # Feed in the file containing all the Conversation IDS to the while loop

# Clean up the temo files
rm -f $allConvosJsonFile
rm -f $allConvoIDsFile
rm -f $fullConvosJsonFile
