const { app } = require('@azure/functions');

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

app.serviceBusQueue('serviceBusQueueTrigger', {
    queueName: '%ServiceBusQueueName%',
    connection: 'ServiceBusConnection',
    handler: async (message, context) => {
        context.log('JavaScript ServiceBus Queue trigger start processing a message:', message);
        
        await delay(30000);
        
        context.log('JavaScript ServiceBus Queue trigger end processing a message');
    }
});
