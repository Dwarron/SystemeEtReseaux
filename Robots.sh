#!/bin/bash

numeroRobot=$1			#numéro du robot passe en paramètre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesRobot=()			#les cartes que le robot possède
carteCourante=0			#la carte jouée par le robot

#méthode qui attend l'envoi des cartes du gestionnaire du jeu et qui les récupères.
waitCartes()
{	
	onAttend=true
	#on boucle tant que l'on n'a pas pu se connecter au gestionnaire du jeu
	while [ $onAttend == "true" ]
	do
		#permet de recevoir les cartes dans l'ordre des robots
		sleep $numeroRobot
		
		#Envoie au gestionnaire du jeu que le robots a recu les cartes en ce connectant au socket
		echo "Robot $numeroRobot a recu ses cartes." | nc localhost 9091 2> /dev/null | echo "Vous avez reçu vos cartes" & onAttend=false
	done
	
	#on trie le fichier qui contient les cartes 
	sort -n tmp/cartePartie -o tmp/cartePartie
	
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); #nombre d'élément dans le fichier
	do	
		#on récupère dans le tableau des cartes du robot, les cartes stockées sur le fichier tmp/cartePartie
		cartesRobot+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo "" > tmp/cartePartie
}

#méthode qui attend le top départ.
waitTopDepart()
{
	#socket ouvert en lecture qui attente le top départ envoyé par le gestionnaire du jeus
	echo "Robot $numeroRobot a recu le top depart." | nc -l -p 9092 | echo "Attente du top départ."
}

#méthode qui essaye de faire jouer le robot au meilleur moment.
#le principe est le suivant :
#1. on récupère la carte d'indice 0, donc la première carte du tableau des cartes du joueur, qui on était trier auparavant.
#2. On génère un nombre aléatoire entre 1 et 6.
#3. On multiplie ce nombre par la valeur de la carte, donc plus la carte va être grand plus le résultat aura des chances d'être grand également. 
#3. On divise l'ensemble par 15 pour ne pas obtenir des nombres trop grands. Et on fait dormir le processus sur ce nombre.
jouerRobot()
{
	#algo pour essayer de faire jouer un robot au bon moment 
	carteCourante=${cartesRobot[0]} 
	
	randomValue=$((1 + $RANDOM % 6))
	time=$(( $(($carteCourante * $randomValue)) / 15 ))
	sleep $time
	
	#ecrit la valeur de la carte dans carteAJouer
	echo $carteCourante > tmp/carteAJouer
	
	#ecrit le num du robot dans numJoueur
	echo $numeroRobot > tmp/numJoueur
	
	onAttend=true
	while [ $onAttend == "true" ]
	do
		#permets la connexion au socket ouvert sur le processus du gestionnaire du jeu, et indique que le robot a joué tel carte.
		#"2> /dev/null" permet de rediriger la sortie des erreurs car si le socket n'arrive pas à se connecter dans le cas ou le socket n'est pas en lecture dans le processus du gestionnaire du jeu. Alors on aura une erreur "Connexion refusé".
		echo "Robot $numeroRobot a jouer la carte $carteCourante." | nc localhost 9093 2> /dev/null | echo "Le robot a joué." & onAttend=false
	done

	#on retire la carte jouée des cartes disponibles pour le robot
	retireCarte $carteCourante
}

#méthode qui vérifie si la partie est terminée.
finGame()
{
	#vérifie si la première ligne du fichier tmp/finGame est égal à la chaine de caractère "fin"
	if [ "$(echo $(cat tmp/finGame) | cut -d" " -f1)" == "fin" ];
	then
		#on écrit dans le terminal l'erreur contenue dans le fichier tmp/finGame
		tail -n 1 tmp/finGame
		partiFini=true
		exit 1
	fi
}

#méthode qui retire la carte passée en paramètre du tableau des cartes.
retireCarte()
{
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes du robot
	cartesTemp=("${cartesRobot[@]}")
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesRobot
	
	#récupération des bonnes valeur c'est-à-dire toutes sauf la carte retirer 
	for i in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$i]} ));
		then
			cartesRobot+=(${cartesTemp[$i]})	
		fi
	done
}

#méthode qui va permettre au robot de démarrer sa partie.
startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top depart
	waitTopDepart
	
	while [ $partieFini == "false" ]
	do
		#on verifie si le robot a encores des cartes
		if (( ${#cartesRobot[*]} == 0 ));
		then
			#apres chaque manche on verifie si la partie est fini
			finGame
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution des cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					#on reverifie ici avant de redistribuer les cartes
					finGame 
					echo "" > tmp/redistribuer
					onAttend=false
					waitCartes
				fi
			done
		else
			#appel la méthode qui va faire jouer le robot 
			jouerRobot
		fi
	done
}

startGame
