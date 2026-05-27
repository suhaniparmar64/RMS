This folder contains sample data for `Integration_Log__c` in SFDX data tree format.

- To import into a scratch or sandbox org run:

```bash
# if you use the default authenticated org
sfdx force:data:tree:import -p force-app/main/default/data/plan.json

# or via npm script
npm run import:sample-data
```

- Note: Deploying metadata (`SFDX: Deploy Source to Org`) does not create records. Use the command above to load sample records into your org.
