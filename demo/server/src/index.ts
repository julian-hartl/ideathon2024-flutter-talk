import * as admin from 'firebase-admin';
import {credential} from 'firebase-admin';
import express, {ErrorRequestHandler, RequestHandler} from "express";
import cors from "cors";
import bodyParser from "body-parser";
import {v4} from "uuid";
import dotEnv from 'dotenv';
import OpenAI from "openai";
import {ChatCompletionMessageParam} from "openai/resources";
import morgan from "morgan";
import applicationDefault = credential.applicationDefault;
import rateLimit from "express-rate-limit";

dotEnv.config({path: '.env'});

admin.initializeApp({
    credential: applicationDefault(),
});

const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});

const app = express();

app.use(cors());
const limiter = rateLimit({
    windowMs: 60 * 1000,
    limit: 2000,
    message: 'Too many requests from this IP, please try again in 1 minute'
});
app.use(limiter);
app.use(bodyParser.json());
app.use(morgan('dev'));


const chatRouter = express.Router();
app.use('/chat', chatRouter);

const authenticate: RequestHandler = async (req, res, next) => {
    const token = req.headers.authorization?.split('Bearer ')[1];
    if (token == null) {
        res.status(401).send('Unauthorized');
        return;
    }
    try {
        const decodedIdToken = await admin.auth().verifyIdToken(token);
        req.user = {
            uid: decodedIdToken.uid
        };
        next();
    } catch (error) {
        res.status(401).send('Unauthorized');
    }
};

interface IChat {
    id: string;
    messages: IMessage[];
    title: string;
    userId: string;
}

class Chat implements IChat {

    constructor(
        public id: string,
        public messages: Message[],
        public title: string,
        public userId: string
    ) {
    }

    public static empty(
        userId: string
    ): Chat {
        return new Chat(v4(), [], 'New Chat', userId);
    }

    public toJson(): IChat {
        return {
            id: this.id,
            messages: this.messages.map(message => message.toJson()),
            title: this.title,
            userId: this.userId,
        }
    }
}

enum Sender {
    User = 'user',
    Bot = 'bot'
}

interface IMessage {
    id: string;
    text: string;
    createdAt: Date;
    userId: string;
    sender: Sender;
}

class Message implements IMessage {

    constructor(
        public id: string,
        public text: string,
        public createdAt: Date,
        public userId: string,
        public sender: Sender,
    ) {
    }

    public static now(
        text: string,
        userId: string,
        sender: Sender,
    ): Message {
        return new Message(v4(), text, new Date(), userId, sender,);
    }

    public toJson(): IMessage {
        return {
            id: this.id,
            text: this.text,
            createdAt: this.createdAt,
            userId: this.userId,
            sender: this.sender,
        }
    }
}

const chats: Chat[] = [];

function findChat(chatId: string, user: { uid: string }) {
    return chats.find(chat => chat.id === chatId && chat.userId === user.uid);
}

chatRouter.post('/', authenticate, (req, res) => {
    const user = req.user!;
    console.log(`User ${user.uid} is creating a chat`)
    const createdChat = Chat.empty(user.uid);
    chats.push(createdChat);
    res.status(200).json(createdChat.toJson());
});

chatRouter.post('/:id/messages/', authenticate, (req, res) => {
    const user = req.user!;
    console.log(`User ${user.uid} is creating a message`);
    const chatId = req.params.id;
    const chat = findChat(chatId, user);
    if (chat == null) {
        res.status(404).send('Chat not found');
        return;
    }
    const message = Message.now(req.body.text, user.uid, Sender.User);
    chat.messages.push(message);
    res.status(200).json(message.toJson());
    console.log(`User ${user.uid} created a message`);
});

chatRouter.get('/:id/response/', authenticate, async (req, res, next) => {
    try {
        const user = req.user!;
        console.log(`User ${user.uid} is getting a response`)
        const chatId = req.params.id;
        const chat = findChat(chatId, user);
        if (chat == null) {
            res.status(404).send('Chat not found');
            return;
        }

        function mapMessages(chat: IChat): ChatCompletionMessageParam[] {
            return chat.messages.map(
                message => ({
                    content: message.text,
                    role: message.sender == 'user' ? 'user' : 'assistant',
                })
            )
        }

        const response = await openai.chat.completions.create({
            model: 'gpt-3.5-turbo',
            messages:
                mapMessages(chat),
        });
        const message = Message.now(response.choices[0].message.content!, user.uid, Sender.Bot);
        chat.messages.push(message);
        res.status(200).json(message.toJson());
        console.log(`User ${user.uid} got a response: ${message.text}`);
    } catch (error) {
        next(error);
    }
});

chatRouter.get('/:id/', authenticate, (req, res) => {
    const user = req.user!;
    console.log(`User ${user.uid} is getting a chat`)
    const chatId = req.params.id;
    const chat = findChat(chatId, user);
    if (chat == null) {
        res.status(404).send('Chat not found');
        return;
    }
    res.status(200).json(chat.toJson());
    console.log(`User ${user.uid} got a chat`);
});

chatRouter.get('/', authenticate, (req, res) => {
    const user = req.user!;
    console.log(`User ${user.uid} is getting chats`)
    const userChats = chats.filter(chat => chat.userId === user.uid);
    res.status(200).json(userChats.map(chat => chat.toJson()));
    console.log(`User ${user.uid} got chats`);
});

const port = 3000;
const errorHandler: ErrorRequestHandler = (err, req, res, next) => {
    console.error(err.stack);
    res.status(500).send('Something broke!');
}
app.use(errorHandler);

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
